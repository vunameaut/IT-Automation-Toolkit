# IT Automation Toolkit

Bo cong cu tu dong hoa tren Windows bang PowerShell. Tap trung vao cac tac vu lap lai cua IT Support: cai phan mem, don dep he thong, sao luu du lieu va toi uu hieu nang.

## Tinh nang

- Cai dat phan mem hang loat bang Winget (co retry, bo qua neu da cai)
- Don dep he thong: temp files, Recycle Bin, DNS cache, Windows Update cache, browser cache
- Sao luu du lieu nguoi dung bang Robocopy (/MIR)
- Toi uu he thong: power plan, visual effects, toi uu o dia, startup, report tinh trang

## Yeu cau

- Windows 10 / Windows 11
- Quyen Administrator
- Ket noi internet (de tai phu thuoc va cai phan mem)
- PowerShell 7+ va Winget se duoc tu dong cai neu thieu

## Cai dat va chay

### Cach 1 (khuyen nghi)
Mo start.bat va chap nhan UAC. Launcher se tu dong:
- Cai App Installer (Winget) neu thieu
- Cai PowerShell 7 neu thieu
- Mo chuong trinh chinh

### Cach 2
```powershell
pwsh -ExecutionPolicy Bypass -File main.ps1
```

## Cau hinh

Sua file config.json:
- softwareList: danh sach phan mem va enabled true/false
- backup: duong dan mac dinh va danh sach thu muc can backup
- cleanup: bat/tat tung tac vu
- logging: bat/tat ghi log va muc log

## Luu y ve sao luu

Robocopy su dung /MIR (mirror). Co the xoa file o thu muc dich neu nguon da xoa. Hay chon dung o dich.

## Log

Log tu dong tao trong thu muc logs, vi du:
```
[2026-05-09 19:48:35] [INFO] Starting installation: Google Chrome
[2026-05-09 19:48:40] [SUCCESS] Google Chrome installed successfully!
[2026-05-09 19:49:01] [ERROR] Installation failed after 3 attempts
```

## Cau truc du an

```
IT-Automation-Toolkit/
├── bootstrap.ps1         # Tu dong cai dat phu thuoc
├── main.ps1              # Menu chinh
├── start.bat             # Launcher
├── config.json           # Cau hinh
├── modules/
│   ├── logger.ps1
│   ├── install.ps1
│   ├── cleanup.ps1
│   ├── backup.ps1
│   └── optimize.ps1
├── logs/                 # Tu dong sinh (da ignore)
└── README.md
```

## License

Du an phuc vu muc dich hoc tap va portfolio.
