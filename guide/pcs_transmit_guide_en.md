# 1000BASE-T PCS Transmit Reference Guide (UVM Verification)

This document provides a detailed technical breakdown of the 1000BASE-T Physical Coding Sublayer (PCS) Transmit function for UVM Reference Model implementation.

---

## 1. Memory Requirements & State Tracking
To accurately predict the output ($A, B, C, D$) at clock cycle $n$, your model must store and update the following "history" states.

### 1.1 Core State Registers
* **Scr_n[32:0] (33 bits)**: The current state of the Side-stream Scrambler LFSR. The next state $Scr_{n+1}$ is computed based on $Scr_n$.
* **cs_n[2:0] (3 bits)**: The internal state of the Convolutional Encoder (Trellis Encoder).

### 1.2 Input Signal Delay Line
To detect state transitions (SSD, ESD, CSReset), you must track:
* **tx_enable_(n-1), tx_enable_(n-2)**: Used to detect rising edges (0->1) and falling edges (1->0).
* **tx_error_(n-1)**: Used to detect errors during an active stream.

### 1.3 Cycle Counter
* **n (Counter)**: Total number of cycles since de-assertion of Reset. Used for `(n mod 2)` calculations, which affects `Sc_n[3:1]` logic.

---

## 2. Signal Generation Path

### 2.1 LFSR State Update ($Scr_n$)
The LFSR is the engine of randomization. Based on the MASTER/SLAVE role:

* **MASTER ($g_M(x) = 1 + x^{13} + x^{33}$)**:
    `Scr_n[0] = Scr_{n-1}[12] ^ Scr_{n-1}[32]`
* **SLAVE ($g_S(x) = 1 + x^{20} + x^{33}$)**:
    `Scr_n[0] = Scr_{n-1}[19] ^ Scr_{n-1}[32]`
* **Shift Operation**: `Scr_n[32:1] = Scr_{n-1}[31:0]`.

### 2.2 Extraction of Pseudo-random Bits ($Sx, Sy, Sg$)
Using the auxiliary polynomial $g(x) = x^3 + x^8$ to "tap" the LFSR into 4-bit arrays:

1.  **Define Source Bits**:
    * `SY_n = Scr_n[0]`
    * `SX_n = Scr_n[4] ^ Scr_n[6]`
    * `SG_n = Scr_n[1] ^ Scr_n[5]`
2.  **Generate 4-bit Arrays (e.g., $Sy_n$)**:
    * `Sy_n[0] = SY_n`
    * `Sy_n[1] = Scr_n[3] ^ Scr_n[8]`
    * `Sy_n[2] = Scr_n[6] ^ Scr_n[16]`
    * `Sy_n[3] = Scr_n[9] ^ Scr_n[14] ^ Scr_n[19] ^ Scr_n[24]`
    *(Note: $Sx_n$ and $Sg_n$ follow the same logic using their respective source bits.)*

### 2.3 Scrambler Octet Generation ($Sc_n[7:0]$)
$Sc_n$ is the final XOR key for data encryption.
* **Fixed Bits**: `Sc_n[7:4] = Sx_n[3:0]`, `Sc_n[0] = Sy_n[0]`.
* **Conditional Bits (Sc_n[3:1])**:
    * **Data Mode (`tx_enable == 1`)**: `Sc_n[3:1] = Sy_n[3:1]`.
    * **Idle Mode (`tx_enable == 0`)**:
        * If `n mod 2 == 0`: `Sc_n[3:1] = Sy_n[3:1]`.
        * If `n mod 2 == 1`: `Sc_n[3:1] = Sx_n[3:1]`.

### 2.4 Convolutional Encoder State ($cs_n$) and Reset Logic
The convolutional encoder is a 3-bit state machine used to generate parity bits for error correction. Its state updates are strictly tied to the `tx_enable` signal.

1.  **Convolutional Reset Trigger (csreset)**:
    Upon the completion of a data frame, the encoder bits must be reset.
    * `csreset_n = (tx_enable_(n-2) == 1) AND (tx_enable_n == 0)`.
2.  **$cs_n$ Generation Rules**:
    The convolutional encoder bits are non-zero only during the transmission of data (i.e., `tx_enable_(n-2) == 1`).
    * `cs_n[0] = cs_{n-1}[2]`
    * `cs_n[1] = Sd_n[6] ^ cs_{n-1}[0]` if `tx_enable_(n-2) == 1`, else `0`.
    * `cs_n[2] = Sd_n[7] ^ cs_{n-1}[1]` if `tx_enable_(n-2) == 1`, else `0`.

### 2.5 Detailed Generation Logic for Encoded Bits ($Sd_n$)
$Sd_n[8:0]$ is a 9-bit word passed to the mapper. The generation of each bit depends on specific conditions like data mode, CSReset, or LPI idle state.

* **Bit 8 (Parity Bit)**:
    * `Sd_n[8] = cs_n[0]`.
* **Bits 7 & 6 (High Data & Reset Markers)**:
    During a CSReset, these bits transmit the previous convolutional states to aid receiver decoding.
    * **Data Mode** (If `csreset_n == 0` and `tx_enable_(n-2) == 1`):
        `Sd_n[7] = Sc_n[7] ^ TXD_n[7]`
        `Sd_n[6] = Sc_n[6] ^ TXD_n[6]`
    * **CSReset Mode** (If `csreset_n == 1`):
        `Sd_n[7] = cs_{n-1}[1]`
        `Sd_n[6] = cs_{n-1}[0]`
    * **Other/Idle**:
        `Sd_n[7] = Sc_n[7]`, `Sd_n[6] = Sc_n[6]`.
* **Bits 5 & 4 (Mid Data)**:
    * If `tx_enable_(n-2) == 1`: `Sd_n[5:4] = Sc_n[5:4] ^ TXD_n[5:4]`.
    * Else: `Sd_n[5:4] = Sc_n[5:4]`.
* **Bit 3 (LPI Request Marker)**:
    Used to scramble data or encode `loc_lpi_req`.
    * If `tx_enable_(n-2) == 1`: `Sd_n[3] = Sc_n[3] ^ TXD_n[3]`.
    * Else if `loc_lpi_req == TRUE` and `tx_mode != SEND_Z`: `Sd_n[3] = Sc_n[3] ^ 1`.
    * Else: `Sd_n[3] = Sc_n[3]`.
* **Bit 2 (Receiver Status Marker)**:
    Used to scramble data or encode `loc_rcvr_status`.
    * If `tx_enable_(n-2) == 1`: `Sd_n[2] = Sc_n[2] ^ TXD_n[2]`.
    * Else if `loc_rcvr_status == OK` and `tx_mode != SEND_Z`: `Sd_n[2] = Sc_n[2] ^ 1`.
    * Else: `Sd_n[2] = Sc_n[2]`.
* **Bit 1 (Update Done & Extension Error Marker)**:
    * If `tx_enable_(n-2) == 1`: `Sd_n[1] = Sc_n[1] ^ TXD_n[1]`.
    * Else if `loc_update_done == TRUE` and `tx_mode != SEND_Z`: `Sd_n[1] = Sc_n[1] ^ 1`.
    * Else: `Sd_n[1] = Sc_n[1] ^ cext_err_n`.
* **Bit 0 (Carrier Extension Marker)**:
    * If `tx_enable_(n-2) == 1`: `Sd_n[0] = Sc_n[0] ^ TXD_n[0]`.
    * Else: `Sd_n[0] = Sc_n[0] ^ cext_n`.

### 2.6 Symbol Mapping ($TA \sim TD$) and Polarity Randomization ($A \sim D$)
This final stage maps the 9-bit word into physical 4D-PAM5 symbols.

1.  **Base Mapping (Look-up Table)**:
    The nine-bit word $Sd_n[8:0]$ is split into indices $Sd_n[6:8]$ and $Sd_n[5:0]$ to look up quinary symbols $(TA_n, TB_n, TC_n, TD_n)$ from IEEE Table 40-1/2.

2.  **Polarity Randomization (Sign Flipping)**:
    The final polarity is determined by both the scrambler bits $Sg_n[3:0]$ and the sign reversal variable $Srev_n$.

    * **Definition of $Srev_n$**:
        The sign reversal is controlled by the variable $Srev_n$ defined as:
        `Srev_n = tx_enable_{n-2} ^ tx_enable_{n-4}` (where ^ is the XOR / Modulo-2 operator)
        *This ensures $Srev_n = 1$ only during the transition periods of the stream (SSD and ESD), triggering a deterministic sign change for the receiver to detect delimiters.*

    The sign multipliers ($SnA_n \sim SnD_n$) are calculated as follows (where $\oplus$ is XOR):
    * $SnA_n = +1 \text{ if } (Sg_n[0] \oplus Srev_n) == 0 \text{ else } -1$
    * $SnB_n = +1 \text{ if } (Sg_n[1] \oplus Srev_n) == 0 \text{ else } -1$
    * $SnC_n = +1 \text{ if } (Sg_n[2] \oplus Srev_n) == 0 \text{ else } -1$
    * $SnD_n = +1 \text{ if } (Sg_n[3] \oplus Srev_n) == 0 \text{ else } -1$

    Final output symbols:
    * **Line A~D**: $A_n = TA_n \times SnA_n$, $B_n = TB_n \times SnB_n$, $C_n = TC_n \times SnC_n$, $D_n = TD_n \times SnD_n$

---

## 3. Special Encodings Breakdown

These states override the standard scrambling path with fixed vector sequences:

* **SSD (Start-of-Stream Delimiter)**:
    * **Condition**: Detected transition of `tx_enable` from 0 to 1.
    * **Behavior**: Transmit SSD1 and SSD2 vectors in the first two cycles of the packet.
* **CSReset (Convolutional State Reset)**:
    * **Condition**: First cycle after `tx_enable` falls from 1 to 0.
    * **Behavior**: Reset internal $cs_n$ to zero and transmit a reset-specific vector.
* **ESD (End-of-Stream Delimiter)**:
    * **Condition**: Occurs immediately after CSReset.
    * **Behavior**: Transmit ESD1 and ESD2 vectors to mark the end of the stream.
* **Error Indication**:
    * **Condition**: `tx_er == 1` while `tx_enable == 1`.
    * **Behavior**: Transmit "Illegal" vector combinations to signal a bad frame to the receiver.

---
