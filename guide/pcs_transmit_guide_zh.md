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
    * $SY_n = Scr_n[0]$
    * $SX_n = Scr_n[4] ^ Scr_n[6]$
    * $SG_n = Scr_n[1] ^ Scr_n[5]$
2.  **生成 4-bit 陣列 (以 $Sy$ 為例)**:
    * $Sy_n[0] = SY_n$
    * $Sy_n[1] = g(SY_n) = Scr_n[3] ^ Scr_n[8]$
    * $Sy_n[2] = g^2(SY_n) = Scr_n[6] ^ Scr_n[16]$
    * $Sy_n[3] = g^3(SY_n) = Scr_n[9] ^ Scr_n[14] ^ Scr_n[19] ^ Scr_n[24]$
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
2.  **資料打亂**: $Scrambled\_Data[7:0] = TXD_n[7:0] ^ Sc_n[7:0]$。
3.  **生成 $cs_n$**: 卷積編碼器是一個 3-bit 的狀態機。根據前一拍 $cs_{n-1}$ 和目前的打亂資料，計算出下一拍狀態。
4.  **生成 $Sd_n[8:0]$**:
    * $Sd_n[7:0] = Scrambled\_Data[7:0]$。
    * $Sd_n[8]$: 這是卷積編碼器根據 $cs_{n-1}$ 算出的同位檢查位元 (Parity bit)，用於糾錯。

### 2.5 符號映射與輸出 ($A, B, C, D$)
1.  **基本映射 ($TA, TB, TC, TD$)**: 將 9-bit 的 $Sd_n$ 作為索引，查表 (IEEE Table 40-1/2) 得到 4 個五進位符號。
2.  **最終隨機反轉**:
    * 根據 $Sg_n[3:0]$ 的值，隨機決定是否反轉 $TA \sim TD$ 的正負號。
    * 例如：若 $Sg_n[0] == 1$，則 $A_n = -TA_n$，否則 $A_n = TA_n$。

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
