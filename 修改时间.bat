@echo off
cd /d "%~dp0"
:: --- 1. 强制 UTF-8 避免中文乱码 ---
chcp 65001 >nul

:: --- 2. 自动请求管理员权限 ---
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    powershell start-process 'cmd.exe' -ArgumentList '/c \"\"%~0\"\"' -verb runas
    exit /B
)

title 全自动同步 (双语修复版)
cls
echo --------------------------------------------------
echo [1/3] 正在初始化环境...
echo [2/3] 正在探测公网 IP 和全球定位 (请耐心等待)...
echo --------------------------------------------------

:: --- 3. 智能提取机制 ---
set "PSFile=%temp%\Full_Sync_%random%.ps1"
powershell -Command "$c = Get-Content '%~f0' -Encoding UTF8; $i = [array]::IndexOf($c, '::POWERSHELL_START_MARKER'); $c[($i+1)..($c.Count-1)] | Set-Content '%PSFile%' -Encoding UTF8"

:: --- 4. 运行提取出的脚本 ---
powershell -NoProfile -ExecutionPolicy Bypass -File "%PSFile%"
if exist "%PSFile%" del "%PSFile%"

:: 任务结束
pause
exit /b

:: =============================================================================
::POWERSHELL_START_MARKER
# =============================================================================
# ↓↓↓ PowerShell 代码开始：已修复双语显示问题 ↓↓↓

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    $web = New-Object System.Net.WebClient
    $web.Encoding = [System.Text.Encoding]::UTF8

    # --- 1. 请求核心数据 (双语) ---
    $api_en = Invoke-RestMethod -Uri 'http://ip-api.com/json/' -TimeoutSec 10
    $api_zh = Invoke-RestMethod -Uri 'http://ip-api.com/json/?lang=zh-CN' -TimeoutSec 10

    # --- 2. 显示网络信息 ---
    $ipv4 = $api_en.query; if (-not $ipv4) { $ipv4 = "未检测到" }
    $ipv6 = "未检测到"; try { $ipv6 = (Invoke-RestMethod -Uri 'http://api6.ipify.org' -TimeoutSec 3).Trim() } catch {}

    Write-Host ("`n[公网 IPv4] " + $ipv4) -ForegroundColor Gray
    Write-Host ("[公网 IPv6] " + $ipv6) -ForegroundColor Gray
    Write-Host "--------------------------------------------------" -ForegroundColor Gray

    $iana = $api_en.timezone
    $countryCode = $api_en.countryCode

    if ($iana) {
        # 显示地理位置
        $geoStr = $api_en.city + ', ' + $api_en.country + ' [' + $api_zh.country + ' ' + $api_zh.regionName + ' ' + $api_zh.city + ']'
        Write-Host ("[地理位置] " + $geoStr) -ForegroundColor Yellow
        
        # 显示 IANA 时区
        Write-Host ("[IANA时区] " + $iana + ' [' + $api_zh.country + ' ' + $api_zh.city + ']') -ForegroundColor Green

        # --- 3. 区域同步 (带中文显示) ---
        if ($countryCode) {
            try {
                $regInfo = New-Object System.Globalization.RegionInfo($countryCode)
                $geoId = $regInfo.GeoId
                Set-WinHomeLocation -GeoId $geoId
                
                # 修改点：增加了 [$api_zh.country] 实现中文显示
                Write-Host ("[区域同步] 已切换至: " + $regInfo.EnglishName + " [" + $api_zh.country + "] (GeoID: $geoId)") -ForegroundColor Cyan
            } catch {
                Write-Host ("[区域同步] 失败: 无法识别国家代码 " + $countryCode) -ForegroundColor Red
            }
        }

        # --- 4. 时区同步 (带中文显示) ---
        # 修改点：恢复了带 | 分隔符的中文映射表
        $map = @{
            'Chicago'='Central Standard Time|中部标准时间'; 'New_York'='Eastern Standard Time|东部标准时间'
            'Los_Angeles'='Pacific Standard Time|太平洋标准时间'; 'Denver'='Mountain Standard Time|山地标准时间'
            'London'='GMT Standard Time|格林威治标准时间'; 'Paris'='Romance Standard Time|罗曼斯标准时间'
            'Berlin'='W. Europe Standard Time|西欧标准时间'; 'Shanghai'='China Standard Time|中国标准时间'
            'Hong_Kong'='China Standard Time|中国标准时间'; 'Taipei'='Taipei Standard Time|台北标准时间'
            'Tokyo'='Tokyo Standard Time|东京标准时间'; 'Seoul'='Korea Standard Time|韩国标准时间'
            'Singapore'='Singapore Standard Time|新加坡标准时间'; 'Bangkok'='SE Asia Standard Time|东南亚标准时间'
            'Sydney'='AUS Eastern Standard Time|澳洲东部时间'
        }
        
        $cityKey = $iana.Split('/')[-1]
        $winZone = ''
        $cnName = ''
        
        # 查表逻辑
        if ($map.ContainsKey($cityKey)) {
            $parts = $map[$cityKey].Split('|')
            $winZone = $parts[0]
            $cnName = $parts[1]
        } else {
            # 模糊匹配
            $cleanCity = $cityKey.Replace('_', ' ')
            $search = Get-TimeZone -List | Where-Object { $_.Id -like "*$cleanCity*" -or $_.DisplayName -like "*$cleanCity*" } | Select-Object -First 1
            if ($search) { 
                $winZone = $search.Id
                $cnName = "自动匹配" 
            }
        }

        if ($winZone) {
            cmd /c tzutil /s "$winZone"
            # 修改点：增加了 [$cnName] 显示中文时区名
            Write-Host ("[时区同步] 已切换至: " + $winZone + " [" + $cnName + "]") -ForegroundColor Cyan
        } else {
            Write-Host "[时区错误] 无法自动匹配时区" -ForegroundColor Red
        }
    }

    # --- 5. 时间校准 ---
    try {
        $res = [System.Net.WebRequest]::Create('https://www.google.com').GetResponse()
        $dt = [DateTime]::Parse($res.Headers['Date']).ToLocalTime()
        Set-Date $dt
        Write-Host ("[时间校准] 当前时间: " + $dt.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Green
    } catch {
        Write-Host "[警告] Google 校时超时" -ForegroundColor Red
    }

    Write-Host "--------------------------------------------------" -ForegroundColor Gray
    Write-Host "任务全部完成！窗口将在 10 秒后自动关闭..." -ForegroundColor White
    Start-Sleep -Seconds 10

} catch {
    Write-Host ("`n[程序异常] " + $_.Exception.Message) -ForegroundColor Red
    Read-Host "请按回车键退出..."
}