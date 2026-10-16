#ifndef TargetArch
  #define TargetArch "x64"
#endif

#define AppVersion "1.0.0"
#define AppIdValue "{{58D4D0E5-6C31-4D9B-9D54-46F31A1F9A57}"

#if TargetArch == "x64"
  #define PackageFolder "mpv-advance-v1-win7-x64"
  #define OutputName "mpv-advance-v1-win7-64bit-setup"
#else
  #define PackageFolder "mpv-advance-v1-win7-x86"
  #define OutputName "mpv-advance-v1-win7-32bit-setup"
#endif

#define PackageSource SourcePath + "\dist\" + PackageFolder

[Setup]
AppId={#AppIdValue}
AppName=视频播放器
AppVersion={#AppVersion}
AppVerName=视频播放器 V1
AppPublisher=mpv-advance
DefaultDirName={autopf}\视频播放器
DefaultGroupName=视频播放器
DisableProgramGroupPage=yes
AllowNoIcons=yes
OutputDir={#SourcePath}\dist
OutputBaseFilename={#OutputName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
MinVersion=6.1sp1
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog commandline
ChangesAssociations=yes
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
UninstallDisplayIcon={app}\runtime\mpv.exe
VersionInfoVersion=1.0.0.0
VersionInfoCompany=mpv-advance
VersionInfoDescription=视频播放器安装程序
VersionInfoProductName=视频播放器
VersionInfoProductVersion={#AppVersion}
VersionInfoOriginalFileName={#OutputName}.exe

#if TargetArch == "x64"
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#else
ArchitecturesAllowed=x86compatible
#endif

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified-6.4.isl"

[Tasks]
Name: "desktopicon"; Description: "在桌面创建快捷方式"; GroupDescription: "快捷方式："; Flags: unchecked
Name: "fileassoc"; Description: "关联媒体文件"; GroupDescription: "文件关联："; Flags: checkedonce
Name: "fileassoc\common"; Description: "常见视频和音频（MP4、MKV、AVI、MP3 等）"; Flags: checkedonce
Name: "fileassoc\surveillance"; Description: "监控录像和码流（DAV、H264、H265、PS、TS 等）"; Flags: checkedonce

[Files]
Source: "{#PackageSource}\runtime\*"; DestDir: "{app}\runtime"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#PackageSource}\portable_config\*"; DestDir: "{app}\portable_config"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#PackageSource}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#PackageSource}\samples\*"; DestDir: "{app}\samples"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#PackageSource}\licenses\*"; DestDir: "{app}\licenses"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#PackageSource}\VERSION.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\视频播放器"; Filename: "{app}\runtime\mpv.exe"; Parameters: "--config-dir=""{app}\portable_config"" --idle=yes"; WorkingDir: "{app}"; IconFilename: "{app}\runtime\mpv.exe"
Name: "{autodesktop}\视频播放器"; Filename: "{app}\runtime\mpv.exe"; Parameters: "--config-dir=""{app}\portable_config"" --idle=yes"; WorkingDir: "{app}"; IconFilename: "{app}\runtime\mpv.exe"; Tasks: desktopicon

[Registry]
Root: HKA; Subkey: "Software\Classes\mpv-advance.Media"; ValueType: string; ValueName: ""; ValueData: "视频播放器媒体文件"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\mpv-advance.Media\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\runtime\mpv.exe,0"
Root: HKA; Subkey: "Software\Classes\mpv-advance.Media\Application"; ValueType: string; ValueName: "ApplicationName"; ValueData: "视频播放器"
Root: HKA; Subkey: "Software\Classes\mpv-advance.Media\Application"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "播放常见媒体和监控录像文件"
Root: HKA; Subkey: "Software\Classes\mpv-advance.Media\Application"; ValueType: string; ValueName: "ApplicationIcon"; ValueData: "{app}\runtime\mpv.exe,0"
Root: HKA; Subkey: "Software\Classes\mpv-advance.Media\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\runtime\mpv.exe"" --config-dir=""{app}\portable_config"" --loop-file=no ""--script-opts=surveillance-external_file=yes,surveillance-overlay=no"" ""%1"""

; 常见视频与音频
Root: HKA; Subkey: "Software\Classes\.mp4"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.mp4\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.mkv"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.mkv\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.avi"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.avi\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.mov"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.mov\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.wmv"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.wmv\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.flv"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.flv\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.webm"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.webm\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.mpg"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.mpg\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.mpeg"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.mpeg\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.m4v"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.m4v\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.vob"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.vob\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.ogv"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.ogv\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.mp3"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.mp3\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.wav"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.wav\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.flac"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.flac\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.aac"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.aac\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.m4a"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.m4a\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.ogg"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.ogg\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.opus"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.opus\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.wma"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common
Root: HKA; Subkey: "Software\Classes\.wma\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\common

; 监控录像与裸码流
Root: HKA; Subkey: "Software\Classes\.dav"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.dav\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.264"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.264\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.h264"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.h264\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.265"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.265\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.h265"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.h265\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.hevc"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.hevc\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.ps"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.ps\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.ts"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.ts\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.mts"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.mts\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.m2ts"; ValueType: string; ValueName: ""; ValueData: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance
Root: HKA; Subkey: "Software\Classes\.m2ts\OpenWithProgids"; ValueType: none; ValueName: "mpv-advance.Media"; Flags: uninsdeletevalue; Tasks: fileassoc\surveillance

[Run]
Filename: "{app}\runtime\mpv.exe"; Parameters: "--config-dir=""{app}\portable_config"" --idle=yes"; WorkingDir: "{app}"; Description: "启动视频播放器"; Flags: nowait postinstall skipifsilent
