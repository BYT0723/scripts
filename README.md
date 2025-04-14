# 脚本

> Dwm 下的一些 Shell 脚本,用于辅助 Dwm

## required

1. 字体

   - rofi 中的字体配置为`JetBrains Mono Nerd Font`以及`Iosevka Nerd Font`,两个字体均可在 Arch 源中安装,`ttf-jetbrains-mono-nerd`和`ttf-iosevka-nerd`
   - 中文字体,如果习惯了思源黑体安装`wqy-zenhei`,如果有其他需求可是配置 archlinuxcn 源，其中有很多中文字体，这边推荐个霞鹜楷体`ttf-lxgw-wenkai`,以及他的等宽字体`ttf-lxgw-wenkai-mono`
   - 以及`rofi/fonts`中的字体,copy 到`~/.local/share/fonts/`中

2. 如下是一些基本依赖

   - `rofi`,类似 dmenu 的一种程序启动启动器,当然还有其他作用.
   - `picom`,窗口合成器，管理桌面中的窗口效果和动画等,初始版`picom`和`picom-git`,只有窗口效果和一些渐变效果,动画这些需要安装 fork 版本,都在 AUR 中,例如`picom-jonaburg-git`和`picom-animation-git`.如果你使用的 fork 版本记得根据 github 中的文档修改`autostart.sh`和`moduel.sh`中 picom 的启动项
   - 通知, 系统通知的统一接口库`libnotify`，无论你安装何种通知程序，都可调用 notify-send 发送通知.当然平铺窗口还是推荐 `dunst`.
   - `xautolock`, 定时自动锁屏，配合 slock 实现锁屏效果，如果想使用其他锁屏，更换 slock,在 autostart.sh 中.`slock`
   - `fcitx5-im`, 输入法的整合包，配置见 ArchWiki，安装需要的语言包，并配置好环境变量即可.`fcitx5-chinese-addons`中文包.
   - `light`, 调节屏幕亮度，这种会有部分问题，如若显卡配置未安装则先安装并配置好显卡，其余问题见 Wiki.
   - `lxsession`(可选), Polkit 的代理，权限管理，将终端中的权限请求转移到 lxsession 下，会解决一下奇怪的问题，可看需求安装.
   - `udiskie`(可选), 自动加载移动设备，加载你的 U 盘、移动硬盘等.
   - `network-manager-applet`(可选), networkmanager 的系统托盘图标.
   - ...

| Name                  | Detail                             | Required                                                                                            |
| :-------------------- | :--------------------------------- | :-------------------------------------------------------------------------------------------------- |
| app.sh                | applications launcher by rofi      | rofi                                                                                                |
| autostart.sh          | dwm autostart script               | picom-git / lxsession / xautolock / slock / network-manager-applet / udiskie / fcitx5-im            |
| brightness.sh         | Screen backlight control           | light                                                                                               |
| clock.sh              | alarm clock by crontab             | libnotify                                                                                           |
| dwm-status-tools.sh   | dwm status bar toolkit             | acpi / alsa-utils / light / networkmanager / mpc / mpd                                              |
| dwm-status-refresh.sh | dwm status composer                | bc                                                                                                  |
| dwm-status.sh         | dwm status refresher               |                                                                                                     |
| module.sh             | system module manager by rofi      | rofi / networkmanager / bluez / bluez-utils / libnotify                                             |
| mpd.sh                | mpd manager by rofi                | mpd / mpc / libnotify                                                                               |
| powermenu.sh          | powermenu by rofi                  | rofi / betterlockscreen / alsa-utils                                                                |
| quicklinks.sh         | quick links by rofi                | firefox or chromium                                                                                 |
| statuscmd.sh          | dwm status bar click event handler | libnotify / alacritty                                                                               |
| term.sh               | terminal launcher                  | st / alacritty                                                                                      |
| touchpad-toggle.sh    | touchpad switcher                  | libnotify                                                                                           |
| volume.sh             | volume controller                  | alsa-utils                                                                                          |
| wallpaper.sh          | wallpaper controller               | feh / xwinwrap / mpv / archlinux-wallpaper / [tabbed](https://github.com/BYT0723/tabbed.git) / surf |
| screenshot.sh         | screen shot tools                  | maim / feh / viewnior / xdotool                                                                     |

> Tips
>
> - tabbed 为本人修改过的，可进行 xmbed 嵌入，若直接使用 AUR 中的 tabbed，在使用 web page 可能出现不可预估的问题；
>   本包需要自行编译，将仓库 clone 到本地，执行`sudo make clean install`即可。

For details, see the comment documentation in the script

<!-- ## previews -->
