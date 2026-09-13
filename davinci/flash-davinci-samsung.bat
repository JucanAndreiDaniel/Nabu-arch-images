@echo off
REM Flash Arch (davinci, Samsung panel): prebuilt U-Boot -> boot, rootfs -> userdata.
fastboot %* getvar product 2>&1 | findstr /r /c:"^product: *davinci" >nul || echo Mismatching image and device
fastboot %* getvar product 2>&1 | findstr /r /c:"^product: *davinci" >nul || exit /B 1
fastboot %* getvar partition-size:boot 2>&1 | findstr /c:"partition-size:boot:" >nul || exit /B 1
fastboot %* getvar partition-size:userdata 2>&1 | findstr /c:"partition-size:userdata:" >nul || exit /B 1
if not exist "%~dp0images\boot-davinci-samsung.img" echo Missing boot-davinci-samsung.img && exit /B 1
if not exist "%~dp0images\rootfs-davinci-samsung.img" echo Missing rootfs-davinci-samsung.img && exit /B 1
echo This will ERASE dtbo and flash boot + userdata. Back up first!
set /p confirm="Type YES to continue: "
if not "%confirm%"=="YES" exit /B 1
fastboot %* erase dtbo || exit /B 1
fastboot %* flash boot %~dp0images\boot-davinci-samsung.img || exit /B 1
fastboot %* flash userdata %~dp0images\rootfs-davinci-samsung.img || exit /B 1
fastboot %* reboot || exit /B 1
