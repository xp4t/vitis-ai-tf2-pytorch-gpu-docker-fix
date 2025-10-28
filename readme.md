# Vitis AI TensorFlow 2 GPU Docker Build Fix

This repository provides a verified fix for the **403 Forbidden error** and subsequent **multi-download failure** during the TensorFlow 2 Docker image build in **Vitis AI GPU environments**.

---

## 🧩 Background

When building the TensorFlow 2 Docker image in Vitis AI, the process frequently fails during Conda environment setup with the following error:

```
RuntimeError: Multi-download failed.
Unable to retrieve repodata (response: 403) for https://repo.anaconda.com/pkgs/main/linux-64/repodata.json
```

This occurs because the default **Anaconda `repo.anaconda.com`** channels have restricted access. The Docker build tries to pull packages from these blocked URLs, causing the entire build to fail.

---

## ⚙️ Key Changes Made

| Location                 | Lines | Description                                                                           |
| ------------------------ | ----- | ------------------------------------------------------------------------------------- |
| **CPU path**             | 29–31 | Removed the default channel and explicitly added `conda-forge` before the VAI channel |
| **ROCm path**            | 56–59 | Removed the default channel and explicitly added `conda-forge`                        |
| **ROCm install command** | 62    | Removed `-c defaults` from the `mamba install` command                                |
| **GPU path (else)**      | 78–81 | Removed default channel and explicitly added `conda-forge`                            |
| **GPU install command**  | 85    | Removed `-c defaults` from the `mamba install` command                                |

These edits completely remove references to the restricted **Anaconda main and R** repositories, relying instead on **conda-forge** and your **local channel**.

---

## 🧠 Root Cause

The issue originated from lines in the build process such as:

```bash
mamba install --no-update-deps -y pydot pyyaml jupyter ipywidgets dill progressbar2 pytest pandas matplotlib pillow -c file:///scratch/conda-channel -c conda-forge -c defaults
```

The inclusion of `-c defaults` forces `mamba` to contact Anaconda’s servers (`repo.anaconda.com`), which are often restricted. This leads to the **403 Forbidden** response and `Multi-download failed` error.

---

## ✅ Fixed Version Example

After the fix, all `mamba` commands should look like this:

```bash
mamba install --no-update-deps -y pydot pyyaml jupyter ipywidgets dill progressbar2 pytest pandas matplotlib pillow \
    -c file:///scratch/conda-channel -c conda-forge
```

This ensures that the build process:

* Uses only `conda-forge` and local channels.
* Avoids any contact with `repo.anaconda.com`.
* Works for CPU, ROCm, and CUDA-based TensorFlow 2 images.

---

## 🧱 Example Build Error (Before Fix)

```
1049.4 RuntimeError: Multi-download failed.
Unable to retrieve repodata (response: 403) for https://repo.anaconda.com/pkgs/main/linux-64/repodata.json
...
ERROR: failed to solve: process "/bin/bash -c if [[ -n \"${TARGET_FRAMEWORK}\" ]]; then  bash ./install_${TARGET_FRAMEWORK}.sh; fi" did not complete successfully: exit code: 1
```

After applying the fix, the error no longer occurs, and the Docker image builds successfully.

---

## 🚀 Usage

Clone and build the fixed image:

```bash
git clone https://github.com/<your-username>/vitis-ai-tf2-docker-fix.git
cd vitis-ai-tf2-docker-fix
docker build -t vitis-ai-tf2-fixed .
```

Run it with GPU support:

```bash
docker run -it --gpus all vitis-ai-tf2-fixed
```

---

## 🧾 Summary

* Removed all access to `repo.anaconda.com`.
* Added `conda-forge` and local channel explicitly.
* Works across CPU, ROCm, and GPU builds.
* Verified fix for TensorFlow 2 path on Vitis AI.

---

## 🪪 License

MIT License — feel free to use, modify, and contribute.

---

## 🤝 Contributing

Pull requests are welcome! If you encounter similar build issues in PyTorch or other Vitis AI Docker variants, feel free to open an issue or contribute to extending this fix.

