# AlphaFold3 Pipeline

集成 **ColabFold (MSA)** + **AlphaFold3** 的一站式蛋白质结构预测工具。

**服务器**: mgmt (219.228.149.80)

## 核心功能

*   **轻量实现**: 无需任何数据/模型装载，一键执行预测。
*   **自动化全流程**: 从 FASTA 直接到结构预测，自动处理 JSON 生成、MSA 计算和 AF3 推理。
*   **远程工作**: 支持直接指定远程输入/输出路径 (e.g., `user@host:/path`)，自动处理文件传输。
*   **多分子类型支持**: 通过简单扩展的 FASTA 格式支持 **DNA, RNA, Ligands (SMILES/CCD)** 混合复合物预测。
*   **批处理**: 支持单任务、批量循环或并行 (parallel) 运行。
*   **模块化设计**: 支持单独运行 MSA、JSON 生成或 AF3 预测步骤。
*   **断点恢复**: 支持从中断点继续执行（`resume` 模式）。

## 快速开始

1.  **配置环境** (首次运行)
    ```bash
    echo 'export PATH="/public/home/jxtang/bin:$PATH"' >> ~/.zshrc
    source ~/.zshrc
    ```

2.  **基础运行** (FASTA -> 结构)
    ```bash
    af3_pipeline.sh full input.fa /tmp/output
    ```

3. **查看帮助** （查看详细的帮助文档）
    ```bash
    af3_pipeline.sh -h
    ```

## 运行模式

| 模式 | 描述 | MSA 来源 |
|------|------|----------|
| `full` | **完整流程** (FASTA -> ColabFold MSA -> AF3) | ColabFold (API/Local) |
| `msa` | 仅计算 MSA | ColabFold (API/Local) |
| `af3` | **原生预测** (FASTA -> AF3) | AF3 内置 MSA 计算 |
| `resume` | 恢复执行（从任务目录继续） | - |
| `json` | 仅转换 FASTA 到 AF3 JSON | 不含 MSA |
| `transfer`| 仅传输结果 | - |

### full vs af3 模式对比

| 特性 | `full` 模式 | `af3` 模式 |
|------|-------------|------------|
| MSA 计算 | ColabFold (API 或 Local) | AlphaFold3 内置 |
| 速度 | 较慢（MSA 预计算） | 较快（一步完成） |
| 灵活性 | 可单独调试 MSA 步骤 | 一体化运行 |
| 推荐场景 | 生产环境、大批量 | 快速测试、小批量 |

## 常见用法示例

### 1. 标准蛋白质预测（推荐）
```bash
# 使用 ColabFold MSA 的完整流程
af3_pipeline.sh full protein.fa /tmp/output
```

### 2. 原生预测（使用 AF3 内置 MSA）
```bash
# 无需预计算 MSA，直接运行 AF3
af3_pipeline.sh af3 protein.fa /tmp/output
```

### 3. 恢复中断的任务
```bash
# MSA 完成后 AF3 中断，从断点继续
af3_pipeline.sh resume /tmp/output/task_name

# 恢复执行并传输结果到远程
af3_pipeline.sh resume /tmp/output/task_name --transfer-to user@host:/path
```

### 4. 远程文件处理 (推荐)
脚本自动下载远程输入文件，计算完成后自动回传结果，无需手动 scp。
```bash
# 输入在远程，输出回传远程
af3_pipeline.sh full user@49.52.20.53:~/data/input.fa user@49.52.20.53:~/results/
```

### 5. 多分子/复合物预测 (DNA/RNA/小分子)
在 FASTA 中使用特殊格式支持非蛋白分子：
```text
>complex_job
# 蛋白链 A
MKFLILLFN...
# 蛋白链 B
:MGLSDGEW...
# DNA 链 (格式: dna|序列)
:dna|ATCGATCG
# 配体 (格式: smiles|SMILES_STRING)
:smiles|CC(=O)OC1=CC=CC=C1C(=O)O
```
所有待预测的序列都应当存储在一个 `xx.fa` 文件中，`xx.fa` 格式如下：
对于单体蛋白而言直接是

```bash
>proteinA
AAAAAAAAAAAAAAAAA
```

对于蛋白复合物 AB （或者更多

```bash
>proteinA:proteinB
AAAAAAAAAAAAAAAAA:BBBBBBBBBB
```
对于蛋白复合物 A 的同源寡聚 (下面两种写法都可以, `|` 右侧的数字表示复制两次)
```bash
>proteinA:proteinA1
AAAAAAAAAAAAAAAAA:AAAAAAAAAAAAAAAAA
>proteinA|2
AAAAAAAAAAAAAAAAA|2
```

对于蛋白质-小分子，下面两种写法都可以，支持 CCD 以及 smiles 输入，`|` 右侧类型表示输入的是 ligand/ccd 还是下面的 rna/dna

```bash
>ProteinA:Ligandsmiles
AAAAAAAAAAAAAAAAA:smiles|C1=NC(=C2C(=N1)N(C=N2)
>ProteinA:LigandCCD
AAAAAAAAAAAAAAA:ccd|ATP
>ProteinA:LigandCCDA:LigandCCDA
AAAAAAAAAAAAAAA:ccd|ATP|2
```
对于蛋白质-核酸

```bash
>ProteinA:NucleDNA
AAAAAAAAAAAAAAA:dna|AAATTGTT
>ProteinA:NucleRNA
AAAAAAAAAAAAAAA:rna|AAAUUGUU
```
同一个 fa 文件中上述的每个任务都可以写在一个文件中， 然后直接运行结构预测：

```bash
af3_pipeline.sh full xx.fa /tmp/output
```

### 6. 远程服务
目的：让任务的输入和输出存储在 `mg` 节点，运行执行程序地址在 `mgmt` 节点

实现：脚本支持通过 `rsync` 实时跨服务器执行，只需输入和输出远端地址即可
```bash
af3_pipeline.sh full user@host:/path/xx.fa. user@host:/path/output
# 比如准备的 fasta 文件在mg节点 /dataStor/home/jxtang/my_task.fa,  输出地址在 mg 节点 /dataStor/home/jxtang/output
# 在 mgmt 执行程序
af3_pipeline.sh full jxtang@49.52.20.53:/dataStor/home/jxtang/my_task.fa jxtang@49.52.20.53:/dataStor/home/jxtang/output
```


### 7. 高效 MSA 策略

API 调用的是 `api.colabfold.com` 提供的 MSA 远程服务，对小批量（小于三十个）友好；

大批量数据建议走本地数据库模式进行 MSA 检索。

```bash
# 使用 API 模式 (默认, 快速)
af3_pipeline.sh full -m api input.fa /tmp/output
# 使用本地数据库模式 (更全面, 需较长时间)
af3_pipeline.sh full -m local input.fa /tmp/output
```

### 8. 仅生成 JSON (用于检查或手动提交)
通过 `json` 模式支持 alphafold 输入文件制作，不含 MSA 与 template
```bash
af3_pipeline.sh json input.fa /tmp/output
```

## 命令手册

```bash
af3_pipeline.sh [模式] [选项] <输入> <输出>
```

| 模式 | 描述 |
|------|------|
| `full` | **完整流程** (FASTA -> ColabFold MSA -> AF3) |
| `msa` | 仅计算 ColabFold MSA |
| `af3` | 原生预测 (FASTA -> AF3，使用 AF3 内置 MSA) |
| `resume` | 恢复执行（从任务目录继续） |
| `json` | 仅转换 FASTA 到 AF3 JSON |
| `transfer`| 仅传输结果 |

**常用选项:**
*   `-g, --gpu ID`: 指定 GPU (e.g., `-g 0`)
*   `-n, --task-name NAME`: 指定任务名 (默认使用输入文件名)
*   `-m, --msa-method METHOD`: MSA 方式 `api` 或 `local` (仅 full/msa 模式)
*   `--no-template`: 禁用模板 (适用于 de novo 蛋白)
*   `--transfer-to PATH`: 完成后传输结果到指定路径
*   `--keep-temp`: 保留临时目录 (调试用)

## 输出结构
```text
/tmp/output/task_name/
├── msa/               # MSA 结果 (json) - full/msa 模式
├── json/              # 输入 JSON - af3 模式
├── af3/               # 结构文件 (cif) 和摘要 (json)
└── logs/              # 运行日志
```

## SSH 免密配置（远程文件传输需要）
```bash
# 生成密钥
ssh-keygen -t rsa -b 4096
# 复制到 mg 服务器
ssh-copy-id your_user@49.52.20.53
# 验证
ssh your_user@49.52.20.53
```