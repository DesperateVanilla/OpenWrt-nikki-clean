# OpenWrt Nikki Clean

Форк [OpenWrt-nikki](https://github.com/nikkinikki-org/OpenWrt-nikki) на актуальной ветке main с установкой из GitHub Releases. [Nikkix](https://github.com/mglants/nikkix) использован как ориентир для заголовков HWID подписки. Остальные изменения сделаны поверх свежего upstream, чтобы новые исправления Nikki можно было регулярно переносить.

## Поддерживаемые сборки

| Устройство | Прошивка | DISTRIB_ARCH | Архив релиза |
| --- | --- | --- | --- |
| NanoPi R3S | FriendlyWrt / OpenWrt 24.10 | aarch64_generic | nikki_aarch64_generic-openwrt-24.10.tar.gz |
| Cudy WR3000S | OpenWrt / FriendlyWrt 24.10 | aarch64_cortex-a53 | nikki_aarch64_cortex-a53-openwrt-24.10.tar.gz |

Требуются firewall4, opkg и ядро с модулями, перечисленными в [nikki/Makefile](nikki/Makefile). Совместимость kmod зависит от конкретной сборки ядра FriendlyWrt: пакетный менеджер должен находить модули именно для вашей прошивки. Поддержка APK и других архитектур в установщике отключена.

## Отличия от upstream

- Удалены встроенные списки China GeoIP и переключатели обхода китайских IP в конфигурации, nftables и LuCI.
- Убраны DNS-правила для CN/!CN и предустановленные китайские DNS. В исходной конфигурации стоят 1.1.1.1 и 9.9.9.9; при желании замените их на свои. Пользовательские профили Mihomo и его функции GeoIP продолжают работать.
- Для каждой подписки можно включить передачу HWID в LuCI. По умолчанию она выключена. При включении отправляются SHA-256 от MAC и заголовки с моделью и версией OpenWrt только серверу этой подписки.
- Пакеты и установщик больше не используют nikkinikki.pages.dev. Фид opkg не публикуется; используется архив GitHub Release.
- Китайские переводы интерфейса сохранены.

## Установка

Проверьте архитектуру на роутере:

~~~sh
. /etc/openwrt_release
echo "$DISTRIB_RELEASE $DISTRIB_ARCH"
~~~

После публикации первого релиза скачайте скрипт отдельно и запустите:

~~~sh
wget -O /tmp/nikki-install.sh https://raw.githubusercontent.com/DesperateVanilla/OpenWrt-nikki-clean/main/install.sh
sh /tmp/nikki-install.sh
~~~

Если GitHub на роутере недоступен, перенесите скрипт и архив нужной архитектуры на роутер любым доступным способом:

~~~sh
NIKKI_ARCHIVE_FILE=/tmp/nikki_aarch64_generic-openwrt-24.10.tar.gz sh /tmp/nikki-install.sh
~~~

Для Cudy замените имя архива на nikki_aarch64_cortex-a53-openwrt-24.10.tar.gz. Установщик проверяет версию OpenWrt, архитектуру и наличие обязательных пакетов в архиве. Если системных зависимостей нет, он обновляет индексы opkg и устанавливает их из репозиториев самой прошивки. Для kmod нужен пакет с ABI именно вашего ядра FriendlyWrt; при ошибке проверьте доступность и совместимость фидов прошивки.

При обновлении с Nikki/Nikkix opkg сохраняет существующий /etc/config/nikki. Если в нём уже настроены китайские DNS или политики CN/!CN, удалите их в настройках DNS LuCI и задайте нужные вам DNS. Новые нейтральные значения применяются к новой конфигурации и не перезаписывают пользовательские настройки.

Для установки конкретного тега задайте NIKKI_RELEASE_TAG, а для другого зеркала релизов — NIKKI_RELEASE_REPO=owner/repo. При наличии NIKKI_ARCHIVE_FILE загрузка из сети не требуется.

## Сборка и обновления

Workflow release-packages собирает только две архитектуры OpenWrt 24.10. После публикации кода в GitHub создайте тег вида v1.26.1-clean.1: сборка прикрепит два архива к GitHub Release. Workflow build-packages позволяет проверить обе сборки вручную.

Если код Nikki или LuCI меняется без повышения PKG_VERSION, увеличьте PKG_RELEASE в соответствующем Makefile перед новым тегом, иначе opkg может считать новый пакет уже установленным.

Workflow sync-upstream ежедневно проверяет nikkinikki-org/OpenWrt-nikki/main и создаёт PR для бесконфликтного обновления. Пока PR ожидает ревью, новые PR не создаются. Конфликт завершает workflow ошибкой для ручного разбора. После ревью PR и слияния создайте новый тег, чтобы выпустить обновлённые пакеты. На форке нужно включить GitHub Actions и разрешить Actions создавать pull requests. Автоматическое слияние не настроено.

Для собственной сборки в OpenWrt SDK добавьте feed из этого репозитория:

~~~sh
echo "src-git nikki https://github.com/DesperateVanilla/OpenWrt-nikki-clean.git;main" >> feeds.conf.default
./scripts/feeds update nikki
./scripts/feeds install -a -p nikki
make package/luci-app-nikki/compile
~~~

Этот репозиторий содержит исходники и CI. До первого успешного GitHub Release ссылку на архив и сетевую установку использовать нельзя. Сборка через OpenWrt SDK и запуск на обоих роутерах должны быть проверены после публикации.

Лицензия: [GPL-3.0](LICENSE). Благодарность авторам OpenWrt-nikki, Mihomo и Nikkix.
