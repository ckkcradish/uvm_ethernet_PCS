# 1000BASE-T PCS Transmit Reference Model 說明文件

> 依據：`doc.pdf` 中 IEEE 802.3-2012 Clause 40.3.1.3 PCS Transmit function 相關頁面整理。  
> 目標：作為 UVM reference model / scoreboard golden model 的實作說明。  
> 原則：本文件只整理 spec 中的 deterministic transmit encoding 流程；Table 40-1 / Table 40-2 的完整 bit-to-symbol mapping 應直接由 spec 表格建立查表資料，不建議手抄重打。

---

## 0. 整體資料路徑

PCS Transmit encoding 的核心流程如下：

```text
GMII / control inputs
        │
        ▼
side-stream scrambler state Scr_n[32:0]
        │
        ▼
generate Sx_n[3:0], Sy_n[3:0], Sg_n[3:0]
        │
        ▼
generate scrambler octet Sc_n[7:0]
        │
        ▼
generate convolutional encoder state cs_n[2:0]
        │
        ▼
generate 9-bit Sd_n[8:0]
        │
        ▼
Table 40-1 / Table 40-2 mapping
        │
        ▼
base quinary symbols TA_n, TB_n, TC_n, TD_n
        │
        ▼
polarity randomization by Sg_n[3:0] and Srev_n
        │
        ▼
final quinary symbols A_n, B_n, C_n, D_n
```

在 reference model 中，**history / delayed signals 很重要**。不要只用 current-cycle input 判斷 SSD、ESD、CSReset、error indication。

---

## 1. Reference Model 需要保存的狀態

### 1.1 Scrambler state

```text
Scr_n[32:0]
```

33-bit transmitter side-stream scrambler state。

PCS Reset 時，spec 說 scrambler state 的 initialization 是 implementation specific，但 **不能全為 0**。

因此 RM 有兩種常見作法：

1. 如果 DUT 初值已知，RM 必須使用相同初值。
2. 如果 spec/testbench 已提供 scrambler reset 行為，RM 要在該 reset event 更新 `n0`。

`n0` 定義為：

```text
n0 = time index of the last transmitter side-stream scrambler reset
```

`Sc_n[3:1]` 會用到 `(n - n0) mod 2`。

---

### 1.2 Convolutional encoder state

```text
cs_n[2:0]
```

3-bit convolutional encoder state。它會影響 `Sd_n[8]`，也會在 CSReset 時被送入 `Sd_n[7:6]`。

---

### 1.3 Delayed tx_enable history

至少保存：

```text
tx_enable_n
tx_enable_{n-1}
tx_enable_{n-2}
tx_enable_{n-3}
tx_enable_{n-4}
```

用途包括：

| 用途 | 需要的 history |
|---|---|
| Data-mode scrambling | `tx_enable_{n-2}` |
| CSReset | `tx_enable_{n-2}`, `tx_enable_n` |
| SSD1 / SSD2 | `tx_enable_n`, `tx_enable_{n-1}`, `tx_enable_{n-2}` |
| ESD1 / ESD2 variants | `tx_enable_{n-2}`, `tx_enable_{n-3}`, `tx_enable_{n-4}` |
| polarity reversal | `tx_enable_{n-2}`, `tx_enable_{n-4}` |

---

### 1.4 Delayed tx_error history

至少保存：

```text
tx_error_n
tx_error_{n-1}
tx_error_{n-2}
tx_error_{n-3}
```

用途包括：

- transmit error indication
- carrier extension error
- CSReset extension/error rows
- ESD extension/error rows

---

### 1.5 Previous Sy value

`Sc_n[3:1]` 在 odd phase 會用到：

```text
Sy_{n-1}[3:1]
```

所以 RM 需要保存前一拍 `Sy`。

---

## 2. Side-stream scrambler 更新

根據 PHY 是 MASTER 或 SLAVE，使用不同 scrambler polynomial。

### 2.1 MASTER PHY

Polynomial：

```text
g_M(x) = 1 + x^13 + x^33
```

更新：

```text
Scr_n[0]    = Scr_{n-1}[12] ^ Scr_{n-1}[32]
Scr_n[32:1] = Scr_{n-1}[31:0]
```

---

### 2.2 SLAVE PHY

Polynomial：

```text
g_S(x) = 1 + x^20 + x^33
```

更新：

```text
Scr_n[0]    = Scr_{n-1}[19] ^ Scr_{n-1}[32]
Scr_n[32:1] = Scr_{n-1}[31:0]
```

---

## 3. Generate Sx_n[3:0], Sy_n[3:0], Sg_n[3:0]

這三組 4-bit vectors 都由 current `Scr_n` 產生。

Auxiliary polynomial：

```text
g(x) = x^3 + x^8
```

### 3.1 Base bits

```text
X_n = Scr_n[4]  ^ Scr_n[6]
Y_n = Scr_n[11] ^ Scr_n[5]
```

注意：`Sg_n[0]` 使用的是 `Y_n = Scr_n[11] ^ Scr_n[5]`，不是 `Scr_n[1] ^ Scr_n[5]`。

---

### 3.2 Sy_n[3:0]

```text
Sy_n[0] = Scr_n[0]
Sy_n[1] = Scr_n[3]  ^ Scr_n[8]
Sy_n[2] = Scr_n[6]  ^ Scr_n[16]
Sy_n[3] = Scr_n[9]  ^ Scr_n[14] ^ Scr_n[19] ^ Scr_n[24]
```

---

### 3.3 Sx_n[3:0]

```text
Sx_n[0] = Scr_n[4]  ^ Scr_n[6]
Sx_n[1] = Scr_n[7]  ^ Scr_n[9]  ^ Scr_n[12] ^ Scr_n[14]
Sx_n[2] = Scr_n[10] ^ Scr_n[12] ^ Scr_n[20] ^ Scr_n[22]
Sx_n[3] = Scr_n[13] ^ Scr_n[15] ^ Scr_n[18] ^ Scr_n[20]
        ^ Scr_n[23] ^ Scr_n[25] ^ Scr_n[28] ^ Scr_n[30]
```

---

### 3.4 Sg_n[3:0]

```text
Sg_n[0] = Scr_n[11] ^ Scr_n[5]
Sg_n[1] = Scr_n[4]  ^ Scr_n[8]  ^ Scr_n[9]  ^ Scr_n[13]
Sg_n[2] = Scr_n[7]  ^ Scr_n[11] ^ Scr_n[17] ^ Scr_n[21]
Sg_n[3] = Scr_n[10] ^ Scr_n[14] ^ Scr_n[15] ^ Scr_n[19]
        ^ Scr_n[20] ^ Scr_n[24] ^ Scr_n[25] ^ Scr_n[29]
```

`Sx` 和 `Sy` 用來產生 scrambler octet `Sc_n[7:0]`。  
`Sg` 用來產生 final quinary symbol 的 polarity randomization。

---

## 4. Generate Sc_n[7:0]

`Sc_n[7:0]` 用來 scramble GMII data octet，也用於 idle/control/training mode code-group generation。

### 4.1 Sc_n[7:4]

```text
if (tx_enable_{n-2} == 1)
    Sc_n[7:4] = Sx_n[3:0]
else
    Sc_n[7:4] = 4'b0000
```

重點：`Sc_n[7:4]` 不是永遠等於 `Sx_n[3:0]`。只有 `tx_enable_{n-2}` 為 1 時才使用 `Sx`。

---

### 4.2 Sc_n[3:1]

```text
if (tx_mode == SEND_Z)
    Sc_n[3:1] = 3'b000
else if ((n - n0) % 2 == 0)
    Sc_n[3:1] = Sy_n[3:1]
else
    Sc_n[3:1] = Sy_{n-1}[3:1] ^ 3'b111
```

重點：odd phase 使用的是 `Sy_{n-1}[3:1] ^ 3'b111`，不是 `Sx_n[3:1]`。

---

### 4.3 Sc_n[0]

```text
if (tx_mode == SEND_Z)
    Sc_n[0] = 1'b0
else
    Sc_n[0] = Sy_n[0]
```

---

## 5. Generate convolutional encoder state cs_n[2:0]

`cs_n` 由 current `Sd_n[6]`、current `Sd_n[7]` 與 previous `cs_{n-1}` 產生。

```text
if (tx_enable_{n-2} == 1)
    cs_n[1] = Sd_n[6] ^ cs_{n-1}[0]
else
    cs_n[1] = 1'b0

if (tx_enable_{n-2} == 1)
    cs_n[2] = Sd_n[7] ^ cs_{n-1}[1]
else
    cs_n[2] = 1'b0

cs_n[0] = cs_{n-1}[2]
```

然後：

```text
Sd_n[8] = cs_n[0]
```

實作提醒：

- `Sd_n[7:6]` 要先依第 6 節公式產生。
- `cs_n[1:2]` 再根據 `Sd_n[6:7]` 與 `cs_{n-1}` 產生。
- `Sd_n[8]` 取 `cs_n[0]`。

---

## 6. Generate Sd_n[8:0]

`Sd_n[8:0]` 是送入 Table 40-1 / Table 40-2 的 9-bit word。

---

### 6.1 CSReset condition

```text
csreset_n = tx_enable_{n-2} & (!tx_enable_n)
```

---

### 6.2 Sd_n[8]

```text
Sd_n[8] = cs_n[0]
```

---

### 6.3 Sd_n[7]

```text
if ((csreset_n == 0) && (tx_enable_{n-2} == 1))
    Sd_n[7] = Sc_n[7] ^ TXD_n[7]
else if (csreset_n == 1)
    Sd_n[7] = cs_{n-1}[1]
else
    Sd_n[7] = Sc_n[7]
```

---

### 6.4 Sd_n[6]

```text
if ((csreset_n == 0) && (tx_enable_{n-2} == 1))
    Sd_n[6] = Sc_n[6] ^ TXD_n[6]
else if (csreset_n == 1)
    Sd_n[6] = cs_{n-1}[0]
else
    Sd_n[6] = Sc_n[6]
```

---

### 6.5 Sd_n[5:4]

```text
if (tx_enable_{n-2} == 1)
    Sd_n[5:4] = Sc_n[5:4] ^ TXD_n[5:4]
else
    Sd_n[5:4] = Sc_n[5:4]
```

---

### 6.6 Sd_n[3]

```text
if (tx_enable_{n-2} == 1)
    Sd_n[3] = Sc_n[3] ^ TXD_n[3]
else if ((loc_lpi_req == TRUE) && (tx_mode != SEND_Z))
    Sd_n[3] = Sc_n[3] ^ 1'b1
else
    Sd_n[3] = Sc_n[3]
```

---

### 6.7 Sd_n[2]

```text
if (tx_enable_{n-2} == 1)
    Sd_n[2] = Sc_n[2] ^ TXD_n[2]
else if ((loc_rcvr_status == OK) && (tx_mode != SEND_Z))
    Sd_n[2] = Sc_n[2] ^ 1'b1
else
    Sd_n[2] = Sc_n[2]
```

---

### 6.8 cext_n and cext_err_n

```text
if ((tx_enable_n == 0) && (TXD_n[7:0] != 8'h0F))
    cext_n = tx_error_n
else
    cext_n = 1'b0
```

```text
if ((tx_enable_n == 0) && (TXD_n[7:0] != 8'h0F) && (loc_lpi_req == FALSE))
    cext_err_n = tx_error_n
else
    cext_err_n = 1'b0
```

---

### 6.9 Sd_n[1]

```text
if (tx_enable_{n-2} == 1)
    Sd_n[1] = Sc_n[1] ^ TXD_n[1]
else if ((loc_update_done == TRUE) && (tx_mode != SEND_Z))
    Sd_n[1] = Sc_n[1] ^ 1'b1
else
    Sd_n[1] = Sc_n[1] ^ cext_err_n
```

---

### 6.10 Sd_n[0]

```text
if (tx_enable_{n-2} == 1)
    Sd_n[0] = Sc_n[0] ^ TXD_n[0]
else
    Sd_n[0] = Sc_n[0] ^ cext_n
```

---

## 7. Table 40-1 / Table 40-2 bit-to-symbol mapping

`Sd_n[8:0]` 會被 mapping 成 base quinary symbols：

```text
TA_n, TB_n, TC_n, TD_n
```

查表索引分成：

```text
Sd_n[6:8]
Sd_n[5:0]
```

其中：

- Table 40-1：even subsets
- Table 40-2：odd subsets

實作建議：

```text
base_symbols = lookup_table(condition, Sd_n[6:8], Sd_n[5:0])
```

`condition` 可能是：

```text
Normal
xmt_err
CSReset
CSExtend
CSExtend_Err
SSD1
SSD2
ESD1
ESD2_Ext_0
ESD2_Ext_1
ESD2_Ext_2
ESD_Ext_Err
Idle/Carrier Extension
```

不要把 special encoding 理解成 bypass 整個 scrambler。比較正確的理解是：

> `Sc`、`Sd`、`cs` 等狀態仍依 spec 產生；到了 table mapping 階段，某些條件會改用 Table 40-1 / Table 40-2 的 special row 做 symbol substitution。

---

## 8. Special symbol substitution 條件

本節整理 Table 40-1 / Table 40-2 special rows 的選擇條件。

---

### 8.1 Error indication：`xmt_err`

當：

```text
tx_error_n == 1
and
(tx_enable_n & tx_enable_{n-2}) == 1
```

使用 table 中 `xmt_err` row。

此時：

```text
Sd_n[5:0] ignored during mapping
```

---

### 8.2 Convolutional Encoder Reset：`CSReset`

當：

```text
csreset_n == 1
and
tx_error_n == 0
```

使用 table 中 `CSReset` row。

此時：

```text
Sd_n[5:0] ignored during mapping
```

---

### 8.3 Carrier Extension during CSReset：`CSExtend` / `CSExtend_Err`

當：

```text
csreset_n == 1
and
tx_error_n == 1
```

代表 convolutional encoder reset condition 同時指示 carrier extension。

接著依 `TXD_n` 選 row：

```text
if (TXD_n == 8'h0F)
    use CSExtend
else
    use CSExtend_Err
```

若在 CSReset 第一個 octet 發生 carrier extension with error，error condition 會在 CSReset 第二個 octet 以及後續兩個 ESD octets 中持續視為存在。

---

### 8.4 Start-of-Stream Delimiter：`SSD1` / `SSD2`

SSD condition：

```text
SSD_n = tx_enable_n & (!tx_enable_{n-2})
```

產生兩個 SSD code-groups：

```text
if (tx_enable_n & (!tx_enable_{n-1}))
    use SSD1

if (tx_enable_{n-1} & (!tx_enable_{n-2}))
    use SSD2
```

概念上：

- `SSD1` 是 tx_enable 上升後的第一個 symbol period。
- `SSD2` 是 tx_enable 上升後的第二個 symbol period。

但 RM 實作時應使用上述 delayed condition，而不是只寫成簡單 edge detect。

---

### 8.5 End-of-Stream Delimiter：ESD rows

ESD condition：

```text
ESD_n = (!tx_enable_{n-2}) & tx_enable_{n-4}
```

代表 last data octet 之後的第三與第四個 symbol periods。

#### 8.5.1 ESD1

當：

```text
(!tx_enable_{n-2}) & tx_enable_{n-3} == 1
```

且此時沒有 carrier extension error indication，使用：

```text
ESD1
```

---

#### 8.5.2 ESD2_Ext_0

當：

```text
(!tx_enable_{n-3})
& tx_enable_{n-4}
& (!tx_error_n)
& (!tx_error_{n-1}) == 1
```

使用：

```text
ESD2_Ext_0
```

---

#### 8.5.3 ESD2_Ext_1

當：

```text
(!tx_enable_{n-3})
& tx_enable_{n-4}
& (!tx_error_n)
& tx_error_{n-1}
& tx_error_{n-2}
& tx_error_{n-3} == 1
```

使用：

```text
ESD2_Ext_1
```

---

#### 8.5.4 ESD2_Ext_2

當：

```text
(!tx_enable_{n-3})
& tx_enable_{n-4}
& tx_error_n
& tx_error_{n-1}
& tx_error_{n-2}
& tx_error_{n-3}
& (TXD_n == 8'h0F) == 1
```

且沒有 carrier extension error indication 時，使用：

```text
ESD2_Ext_2
```

---

#### 8.5.5 ESD_Ext_Err

當 ESD 期間指示 carrier extension error，使用：

```text
ESD_Ext_Err
```

Spec 描述的 error indication 條件包含：

```text
tx_error_n
& tx_error_{n-1}
& tx_error_{n-2}
& (TXD_n != 8'h0F)
```

以及延伸到更長 history 的條件：

```text
tx_error_n
& tx_error_{n-1}
& tx_error_{n-2}
& tx_error_{n-3}
& (TXD_n != 8'h0F)
```

實作時，建議把 `ESD_Ext_Err` 優先於一般 ESD2_Ext rows 判斷，以避免 error row 被 normal extension row 覆蓋。

---

## 9. Polarity randomization：generate A_n, B_n, C_n, D_n

Table mapping 先產生 base symbols：

```text
TA_n, TB_n, TC_n, TD_n
```

接著用 `Sg_n[3:0]` 和 `Srev_n` 決定每個 symbol 的 sign multiplier。

---

### 9.1 Srev_n

```text
Srev_n = tx_enable_{n-2} ^ tx_enable_{n-4}
```

這個 reversal 會讓 idle mode plus SSD 的 code-groups 和其他 symbol periods 有區別。

---

### 9.2 Sign multipliers

```text
if ((Sg_n[0] ^ Srev_n) == 0)
    SnA_n = +1
else
    SnA_n = -1

if ((Sg_n[1] ^ Srev_n) == 0)
    SnB_n = +1
else
    SnB_n = -1

if ((Sg_n[2] ^ Srev_n) == 0)
    SnC_n = +1
else
    SnC_n = -1

if ((Sg_n[3] ^ Srev_n) == 0)
    SnD_n = +1
else
    SnD_n = -1
```

---

### 9.3 Final symbols

```text
A_n = TA_n * SnA_n
B_n = TB_n * SnB_n
C_n = TC_n * SnC_n
D_n = TD_n * SnD_n
```

---

## 10. Recommended RM update order

為了避免 cycle dependency 寫錯，建議 RM 每拍照以下順序運算：

```text
1. Read current inputs:
   TXD_n, tx_enable_n, tx_error_n,
   tx_mode, loc_lpi_req, loc_rcvr_status, loc_update_done

2. Update / compute current Scr_n from previous Scr_{n-1}.

3. Generate Sy_n, Sx_n, Sg_n from Scr_n.

4. Generate Sc_n[7:0].

5. Compute csreset_n.

6. Generate Sd_n[7:0].

7. Generate cs_n[2:0].

8. Set Sd_n[8] = cs_n[0].

9. Select mapping condition:
   xmt_err / CSReset / CSExtend / SSD / ESD / Normal / Idle-Carrier-Extension.

10. Lookup Table 40-1 / Table 40-2 to get TA_n~TD_n.

11. Compute Srev_n and SnA_n~SnD_n.

12. Compute final A_n~D_n.

13. Commit states for next cycle:
    Scr_{n-1}      <= Scr_n
    cs_{n-1}       <= cs_n
    Sy_{n-1}       <= Sy_n
    tx_enable hist <= shifted history
    tx_error hist  <= shifted history
```

注意：第 6 與第 7 步的順序很重要，因為 `cs_n[1:2]` 使用 current `Sd_n[6:7]`。

---

## 11. Implementation checklist

Reference model 實作完成後，至少檢查以下項目：

- [ ] MASTER / SLAVE scrambler polynomial 是否選對。
- [ ] Scrambler reset 初值是否和 DUT/testbench 一致，且不是 all-zero。
- [ ] `Sg_n[0]` 是否使用 `Scr_n[11] ^ Scr_n[5]`。
- [ ] `Sc_n[7:4]` 是否只有在 `tx_enable_{n-2}` 為 1 時使用 `Sx_n[3:0]`。
- [ ] `Sc_n[3:1]` odd phase 是否使用 `Sy_{n-1}[3:1] ^ 3'b111`。
- [ ] `Sc_n[0]` 與 `Sc_n[3:1]` 是否處理 `tx_mode == SEND_Z`。
- [ ] `cs_n[1:2]` 是否使用 current `Sd_n[6:7]`，不是 previous `Sd`。
- [ ] `csreset_n` 是否為 `tx_enable_{n-2} & !tx_enable_n`。
- [ ] `cext_n` / `cext_err_n` 是否依 `tx_enable_n`、`TXD_n != 8'h0F`、`loc_lpi_req` 產生。
- [ ] SSD 是否用 delayed tx_enable condition 判斷 `SSD1` / `SSD2`。
- [ ] ESD 是否保存到 `tx_enable_{n-4}` 與 `tx_error_{n-3}`。
- [ ] Special rows 是否在 Table mapping 階段選擇，而不是錯誤地 bypass 所有 state update。
- [ ] `Srev_n` 是否為 `tx_enable_{n-2} ^ tx_enable_{n-4}`。
- [ ] Final output 是否為 `TA~TD` 乘上 `SnA~SnD`。

---

## 12. 最重要的實作觀念

這個 PCS Transmit encoder 不是單純 combinational mapping。它同時依賴：

1. current inputs
2. scrambler state
3. convolutional encoder state
4. delayed `tx_enable`
5. delayed `tx_error`
6. previous `Sy`
7. table special row conditions

所以 RM 的核心不是只把 `TXD` 丟進 table，而是要精確維護 transmitter 的 cycle-by-cycle state。
