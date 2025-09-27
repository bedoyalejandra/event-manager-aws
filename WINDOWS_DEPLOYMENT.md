# 🪟 Windows Deployment Guide - Event Manager AWS

This guide provides Windows-specific instructions for deploying the Event Manager AWS application.

## 📋 Prerequisites

### Required Software
- **AWS CLI v2** - Download from [AWS CLI Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- **Node.js** (v18 or higher) - Download from [nodejs.org](https://nodejs.org/)
- **PowerShell 5.1+** (included in Windows 10/11) or **PowerShell 7+**
- **Git** (optional but recommended) - Download from [git-scm.com](https://git-scm.com/)

### AWS Setup
1. **Configure AWS CLI:**
   ```cmd
   aws configure
   ```
   Enter your:
   - AWS Access Key ID
   - AWS Secret Access Key
   - Default region (e.g., `us-west-2`)
   - Default output format (e.g., `json`)

2. **Verify credentials:**
   ```cmd
   aws sts get-caller-identity
   ```

## 🚀 Deployment Options

You have **3 options** to deploy on Windows:

### Option 1: PowerShell Script (Recommended)

This is the most feature-complete option, equivalent to the bash script.

```powershell
# Open PowerShell as Administrator (recommended)
cd path\to\event-manager-aws

# Run with default settings (dev environment)
.\scripts\deploy.ps1

# Run with custom parameters
.\scripts\deploy.ps1 -Environment prod -DBUsername admin -Debug
```

#### PowerShell Parameters:
- `-Environment` - Deployment environment (`dev` or `prod`)
- `-DBUsername` - Database username (default: `event_admin`)
- `-AWSRegion` - AWS region (default: from AWS config)
- `-Debug` - Enable debug output

### Option 2: Batch File

Simple batch script for basic deployment:

```cmd
# Open Command Prompt as Administrator
cd path\to\event-manager-aws

# Run with default settings
scripts\deploy.bat

# Run with parameters
scripts\deploy.bat dev event_admin us-west-2
```

#### Batch Parameters (positional):
1. Environment (`dev` or `prod`)
2. Database username
3. AWS region

### Option 3: WSL (Windows Subsystem for Linux)

If you have WSL installed, you can use the original bash scripts:

```bash
# In WSL terminal
cd /mnt/c/path/to/event-manager-aws
./scripts/deploy.sh
```

## 🔧 Troubleshooting

### Common Windows Issues

#### PowerShell Execution Policy
If you get an execution policy error:

```powershell
# Check current policy
Get-ExecutionPolicy

# Allow script execution (run as Administrator)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Or bypass for single execution
powershell -ExecutionPolicy Bypass -File .\scripts\deploy.ps1
```

#### Path Issues
Windows uses backslashes (`\`) in paths. The scripts handle this automatically, but if you encounter issues:

```powershell
# Use full paths
.\scripts\deploy.ps1

# Or change directory first
cd scripts
.\deploy.ps1
```

#### Long Path Names
If you encounter "path too long" errors:

1. **Enable long path support** (Windows 10 1607+):
   ```cmd
   # Run as Administrator
   reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f
   ```

2. **Or move project closer to root:**
   ```
   C:\aws\event-manager-aws\
   ```

#### Node.js/npm Issues
```cmd
# Verify Node.js installation
node --version
npm --version

# Clear npm cache if needed
npm cache clean --force

# Update npm
npm install -g npm@latest
```

#### ZIP Creation Issues
The PowerShell script uses built-in compression. If it fails:

```powershell
# Alternative: Use 7-Zip if installed
& "C:\Program Files\7-Zip\7z.exe" a lambda-functions.zip *.* -x!*.zip -x!package-lock.json

# Or install PowerShell Archive module
Install-Module Microsoft.PowerShell.Archive -Force
```

### AWS-Specific Issues

#### Credentials Not Found
```cmd
# Check AWS credentials
aws configure list

# Reconfigure if needed
aws configure

# Or set environment variables
set AWS_ACCESS_KEY_ID=your_access_key
set AWS_SECRET_ACCESS_KEY=your_secret_key
set AWS_DEFAULT_REGION=us-west-2
```

#### Region Issues
```cmd
# Check current region
aws configure get region

# Set region explicitly
aws configure set region us-west-2
```

#### Permissions Issues
Make sure your AWS user has the necessary permissions:
- CloudFormation full access
- IAM permissions
- S3 full access
- Lambda full access
- RDS full access
- API Gateway full access
- Cognito full access

## 📁 File Structure After Deployment

```
event-manager-aws/
├── scripts/
│   ├── deploy.ps1          # PowerShell deployment script
│   ├── utils.ps1           # PowerShell utilities
│   ├── deploy.bat          # Batch deployment script
│   ├── deploy.sh           # Original bash script
│   └── utils.sh            # Original bash utilities
├── infra/                  # CloudFormation templates
├── src/                    # Lambda functions source code
└── lambda-functions.zip    # Created during deployment
```

## ⚡ Performance Tips

### Speed Up Deployment

1. **Use SSD storage** for faster file operations
2. **Run from local drive** (not network drive)
3. **Close unnecessary applications** during deployment
4. **Use PowerShell ISE or VS Code** for better script debugging

### Reduce Deployment Time

1. **Reuse existing resources** when possible
2. **Skip unchanged stacks** in subsequent deployments
3. **Use smaller RDS instance** for development (`db.t3.micro`)

## 🔐 Security Considerations

### Windows-Specific Security

1. **Run PowerShell as Administrator** for full functionality
2. **Use Windows Defender exclusions** for the project folder during deployment
3. **Ensure PowerShell execution policy** allows script execution
4. **Keep AWS credentials secure** - don't commit them to Git

### Best Practices

1. **Use environment variables** for sensitive data
2. **Rotate AWS credentials** regularly
3. **Use least-privilege IAM policies**
4. **Enable MFA** on your AWS account

## 🆘 Getting Help

### Check Logs

PowerShell and batch scripts provide detailed logging:

```powershell
# Enable verbose output
.\scripts\deploy.ps1 -Debug

# Check Windows Event Viewer for system issues
eventvwr.msc
```

### Common Log Locations

- **PowerShell errors**: Console output
- **AWS CLI logs**: `%USERPROFILE%\.aws\cli\cache\`
- **npm logs**: `%APPDATA%\npm-cache\_logs\`
- **Windows temp files**: `%TEMP%\`

### Support Resources

1. **AWS Documentation**: [docs.aws.amazon.com](https://docs.aws.amazon.com)
2. **PowerShell Help**: `Get-Help` commands
3. **Node.js Issues**: [nodejs.org/en/docs/](https://nodejs.org/en/docs/)
4. **AWS CLI Troubleshooting**: [AWS CLI Error Handling](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-troubleshooting.html)

## 🎯 Quick Start Commands

```powershell
# Complete Windows deployment in one command
cd C:\your\project\path
.\scripts\deploy.ps1 -Environment dev -Debug

# Verify deployment
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE
```

---

**Note**: The PowerShell script (`deploy.ps1`) is functionally equivalent to the bash script (`deploy.sh`) and includes all the same features including database creation, initialization, and complete infrastructure deployment.
