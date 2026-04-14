# 1000BASE-T PCS Transmit 完整驗證指南 (UVM Reference Model)

本文件旨在為 UVM 驗證環境中的 Reference Model (C/C++ 或 SystemVerilog 實作) 提供詳細的邏輯指引。

---

## 1. 記憶狀態需求 (Memory & States)
在每一拍 ($n$) 運算時，你的模型必須儲存並更新以下狀態。若不儲存這些「過去的資訊」，將無法正確預測輸出。

### 1.1 核心狀態暫存器
* **Scr_n[32:0] (33 bits)**: 儲存當前 LFSR 的狀態。下一拍的狀態 $Scr_{n+1}$ 是基於當前的 $Scr_n$ 計算。
* **cs_n[2:0] (3 bits)**: 卷積編碼器 (Convolutional Encoder) 的內部狀態。

### 1.2 輸入訊號延遲線
為了判斷 SSD、ESD 以及 CSReset 的觸發點，你需要記住：
* **tx_enable_(n-1), tx_enable_(n-2)**: 偵測 `tx_enable` 的升緣 (0->1) 或降緣 (1->0)。
* **tx_error_(n-1)**: 偵測傳輸過程中是否發生錯誤。

### 1.3 週期計數器
* **n (Counter)**: 記錄自 Reset 釋放後的總週期數。這用於計算 `(n mod 2)`，這會直接影響 `Sc_n[3:1]` 的生成邏輯。

---

## 2. 訊號生成路徑 (Signal Generation Path)

### 2.1 LFSR 狀態更新 ($Scr_n$)
LFSR 是所有隨機訊號的源頭。根據 Master 或 Slave 身份，公式如下：

* **MASTER ($g_M(x) = 1 + x^{13} + x^{33}$)**:
    `Scr_n[0] = Scr_{n-1}[12] ^ Scr_{n-1}[32]`
* **SLAVE ($g_S(x) = 1 + x^{20} + x^{33}$)**:
    `Scr_n[0] = Scr_{n-1}[19] ^ Scr_{n-1}[32]`
* **更新動作**: 其餘位元向右平移一格：`Scr_n[32:1] = Scr_{n-1}[31:0]`。

### 2.2 提取基礎隨機位元 ($Sx, Sy, Sg$)
利用輔助公式 $g(x) = x^3 + x^8$，從 LFSR 的不同位置「抽頭」產生 4-bit 陣列：

1.  **定義源頭 (Source Bits)**:
    * `SY_n = Scr_n[0]`
    * `SX_n = Scr_n[4] ^ Scr_n[6]`
    * `SG_n = Scr_n[1] ^ Scr_n[5]`
2.  **生成 4-bit 陣列 (以 $Sy$ 為例)**:
    * `Sy_n[0] = SY_n`
    * `Sy_n[1] = Scr_n[3] ^ Scr_n[8]`
    * `Sy_n[2] = Scr_n[6] ^ Scr_n[16]`
    * `Sy_n[3] = Scr_n[9] ^ Scr_n[14] ^ Scr_n[19] ^ Scr_n[24]`
    *(註：$Sx_n$ 與 $Sg_n$ 的生成邏輯相同，僅源頭分別替換為 $SX_n$ 與 $SG_n$。)*

### 2.3 攪亂密鑰生成 ($Sc_n[7:0]$)
$Sc_n$ 是最終用來與資料 XOR 的密鑰。
* **高低位元**: `Sc_n[7:4] = Sx_n[3:0]`, `Sc_n[0] = Sy_n[0]`。
* **關鍵條件位元 (Sc_n[3:1])**:
    * **Data Mode (`tx_enable == 1`)**: `Sc_n[3:1] = Sy_n[3:1]`。
    * **Idle Mode (`tx_enable == 0`)**:
        * 若 `n mod 2 == 0`: `Sc_n[3:1] = Sy_n[3:1]`。
        * 若 `n mod 2 == 1`: `Sc_n[3:1] = Sx_n[3:1]`。

### 2.4 卷積編碼器 ($cs_n$) 與編碼資料 ($Sd_n$)
1.  **輸入資料**: $TXD_n[7:0]$。
2.  **資料打亂**: $Scrambled Data[7:0] =$ `TXD_n[7:0] ^ Sc_n[7:0]`。
3.  **生成 $cs_n$**: 卷積編碼器是一個 3-bit 的狀態機。根據前一拍 $cs_{n-1}$ 和目前的打亂資料，計算出下一拍狀態。
4.  **生成 $Sd_n[8:0]$**:
    * $Sd_n[7:0] = Scrambled Data[7:0]$。
    * $Sd_n[8]$: 這是卷積編碼器根據 $cs_{n-1}$ 算出的同位檢查位元 (Parity bit)，用於糾錯。

### 2.5 卷積編碼器狀態 ($cs_n$) 與重置邏輯
卷積編碼器 (Convolutional Encoder) 是一個 3-bit 的狀態機，負責產生糾錯用的同位檢查位元。它的狀態更新與 `tx_enable` 息息相關。

1.  **卷積重置觸發 (csreset)**:
    當資料傳輸結束時，必須重置編碼器狀態 。
    * `csreset_n = (tx_enable_(n-2) == 1) AND (tx_enable_n == 0)` 。
2.  **$cs_n$ 生成公式**:
    只有在傳輸資料時 (即 `tx_enable_(n-2) == 1`)，狀態才會更新；否則歸零 。
    * `cs_n[0] = cs_{n-1}[2]` 
    * `cs_n[1] = Sd_n[6] ^ cs_{n-1}[0]` (如果 `tx_enable_(n-2) == 1`)，否則為 `0` 。
    * `cs_n[2] = Sd_n[7] ^ cs_{n-1}[1]` (如果 `tx_enable_(n-2) == 1`)，否則為 `0` 。

### 2.6 編碼資料 ($Sd_n$) 各位元詳細生成邏輯
`Sd_n[8:0]` 是即將送去查表的 9-bit 向量 。它的每一位元都有特定的生成條件，會根據是否在傳送資料、是否在重置、或是休眠 (LPI) 等狀態而改變。

* **Bit 8 (同位位元)**:
    * `Sd_n[8] = cs_n[0]` 。
* **Bits 7 & 6 (高位元資料與重置標記)**:
    這兩個位元在發生 `csreset` 時，會被用來傳遞前一拍的卷積狀態，以便接收端完美解碼 。
    * **Data Mode** (若 `csreset_n == 0` 且 `tx_enable_(n-2) == 1`):
        `Sd_n[7] = Sc_n[7] ^ TXD_n[7]` 
        `Sd_n[6] = Sc_n[6] ^ TXD_n[6]` 
    * **CSReset Mode** (若 `csreset_n == 1`):
        `Sd_n[7] = cs_{n-1}[1]` 
        `Sd_n[6] = cs_{n-1}[0]`
    * **Other/Idle**:
        `Sd_n[7] = Sc_n[7]`, `Sd_n[6] = Sc_n[6]`。
* **Bits 5 & 4 (中位元資料)**:
    * 若 `tx_enable_(n-2) == 1`: `Sd_n[5:4] = Sc_n[5:4] ^ TXD_n[5:4]`。
    * 否則: `Sd_n[5:4] = Sc_n[5:4]`。
* **Bit 3 (LPI 請求標記)**:
    除了打亂資料，也用來指示是否請求低功耗模式。
    * 若 `tx_enable_(n-2) == 1`: `Sd_n[3] = Sc_n[3] ^ TXD_n[3]`。
    * 若 `loc_lpi_req == TRUE` 且 `tx_mode != SEND_Z`: `Sd_n[3] = Sc_n[3] ^ 1`。
    * 否則: `Sd_n[3] = Sc_n[3]`。
* **Bit 2 (接收器狀態標記)**:
    用來在閒置時告訴對方自己的接收器狀態。
    * 若 `tx_enable_(n-2) == 1`: `Sd_n[2] = Sc_n[2] ^ TXD_n[2]`。
    * 若 `loc_rcvr_status == OK` 且 `tx_mode != SEND_Z`: `Sd_n[2] = Sc_n[2] ^ 1`。
    * 否則: `Sd_n[2] = Sc_n[2]`。
* **Bit 1 (更新完成與載波延伸錯誤標記)**:
    * 若 `tx_enable_(n-2) == 1`: `Sd_n[1] = Sc_n[1] ^ TXD_n[1]`。
    * 若 `loc_update_done == TRUE` 且 `tx_mode != SEND_Z`: `Sd_n[1] = Sc_n[1] ^ 1`。
    * 否則: `Sd_n[1] = Sc_n[1] ^ cext_err_n` 。
* **Bit 0 (載波延伸標記)**:
    * 若 `tx_enable_(n-2) == 1`: `Sd_n[0] = Sc_n[0] ^ TXD_n[0]` 。
    * 否則: `Sd_n[0] = Sc_n[0] ^ cext_n` 。

### 2.7 符號映射 ($TA \sim TD$) 與極性隨機反轉 ($A \sim D$)
此階段將 9-bit 數位訊號轉換為要在實體線路傳輸的 4D-PAM5 符號。

1.  **查表轉換 (Base Mapping)**:
    將 9-bit 的 $Sd_n[8:0]$ 拆分為兩部分：索引值 `$Sd_n[6:8]$` 與 `$Sd_n[5:0]$` 。
    拿這組索引去對照 IEEE 規範的 Table 40-1 與 Table 40-2，即可得出四個基本五進位符號 $(TA_n, TB_n, TC_n, TD_n)$。符號的數值僅限於 `{+2, +1, 0, -1, -2}` 。

2.  **極性隨機反轉 (Polarity Randomization)**:
    為了確保訊號在線路上不會產生直流偏差 (DC bias)，必須隨機反轉這些符號的正負號。這是透過先前準備好的 4-bit 隨機密鑰 $Sg_n[3:0]$ 來達成的。
    詳細機制如下 (1 代表反轉，0 代表維持原樣)：
    * **Line A**: `A_n = TA_n \times (-1)^{Sg_n[0]}`
    * **Line B**: `B_n = TB_n \times (-1)^{Sg_n[1]}`
    * **Line C**: `C_n = TC_n \times (-1)^{Sg_n[2]}`
    * **Line D**: `D_n = TD_n \times (-1)^{Sg_n[3]}`

---

## 3. 特殊狀態詳細說明 (Special Encodings)

這些狀態會無視正常的 Scrambler 流程，改為發送特定向量：

* **SSD (Start-of-Stream Delimiter)**:
    * **條件**: 當偵測到 `tx_enable` 從 0 變 1。
    * **行為**: 在資料的前兩個週期發送特定的 SSD1 (A=+2, B=+2, C=+2, D=+2) 與 SSD2 (A=+2, B=+2, C=-2, D=-2)。
* **CSReset (Convolutional State Reset)**:
    * **條件**: 當 `tx_enable` 從 1 變 0 之後的第一個週期。
    * **行為**: 強制將 $cs_n$ 內部暫存器清零，並發送特定向量以利接收端結尾。
* **ESD (End-of-Stream Delimiter)**:
    * **條件**: 緊接在 CSReset 之後。
    * **行為**: 發送 ESD1 與 ESD2 向量，標誌資料流正式結束。
* **Error Indication**:
    * **條件**: `tx_er == 1` 且 `tx_enable == 1`。
    * **行為**: 發送一組預定義的「非法組合」，讓接收端知道這份資料無效。

---
