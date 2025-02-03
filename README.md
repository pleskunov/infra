# infra

# Description

A collection of tools to automate the process of installation and deployment.

## arch.sh

This simple shell script automates process of Arch Linux installation.

### Usage

Download the script using **curl** on the Arch Linux live environment and run it with the **target device** (e.g. /dev/sda) and the **hostname** as arguments:

```bash
curl --proto '=https' --tlsv1.2 -sSf -o arch.sh https://raw.githubusercontent.com/pleskunov/infra/refs/heads/main/arch.sh && chmod +x ./arch.sh && bash ./arch.sh /dev/sda my-archbox
```
