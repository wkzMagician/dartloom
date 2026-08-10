# dartloom_sync_webdav

Official Dartloom adapter. Applications normally select it through `dartloom cap`
instead of importing it directly from feature code.

On Android, the adapter contributes `android.permission.INTERNET` through its
library manifest. Gradle merges the declaration into applications that enable
the WebDAV adapter, including release builds.
