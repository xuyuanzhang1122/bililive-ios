# iOS Backup / Restore Backend API Contract

This document describes backend work required by the iOS backup and restore UI. The iOS client already handles local JSON export/import and calls these endpoints when available.

## Backup Package

The iOS client sends and reads a JSON package with this shape:

```json
{
  "schemaVersion": 1,
  "exportedAt": "2026-05-04T08:00:00Z",
  "iosConfig": {
    "serverURL": "http://192.168.1.10:8080",
    "lanURL": "http://192.168.1.10:8080",
    "publicURL": "https://image.xumy.art",
    "autoSwitchNetwork": true
  },
  "server": {
    "rpc_bind": ":8080",
    "out_put_path": "./recordings",
    "app_data_path": ".appdata",
    "live_rooms": [
      {
        "url": "https://live.douyin.com/810339218646",
        "is_listening": false
      }
    ]
  }
}
```

The package must not include API Keys, cookies, signed media URLs, watch history, or other secrets.

## Required Endpoints

### `POST /api/backups`

Stores a backup package on the current bililive-go server and returns a stable lookup ID.

Request body: the backup package JSON.

Success response:

```json
{
  "id": "bgo_20260504_abcd1234",
  "created_at": "2026-05-04T08:00:00Z"
}
```

### `GET /api/backups/{id}`

Returns the backup package for the supplied ID.

Success response: the backup package JSON.

### `POST /api/backups/restore`

Restores a backup either from a stored ID or from an inline package.

Request body with ID:

```json
{ "id": "bgo_20260504_abcd1234" }
```

Request body with inline package:

```json
{ "package": { "...": "backup package" } }
```

Expected behavior:

- Validate `schemaVersion`.
- Validate `rpc_bind`, `out_put_path`, and `app_data_path`.
- Write restored server config and live room list.
- Restart or reload bililive-go when required.
- Return a restore status. If restart is async, include `job_id`.

Success response:

```json
{
  "status": "restarting",
  "job_id": "restore_123",
  "message": "配置已写入，正在重启服务"
}
```

### `GET /api/backups/restore/status/{job_id}`

Returns the latest restore/restart status.

Success response:

```json
{
  "status": "completed",
  "job_id": "restore_123",
  "message": "服务已恢复"
}
```

Recommended statuses: `pending`, `running`, `restarting`, `completed`, `failed`.

## Existing APIs Used by iOS

- `GET /api/config`: iOS reads `rpc.bind`, `out_put_path`, `app_data_path`, and `live_rooms`.
- `GET /api/lives`: iOS refreshes live room status and list state.
- `GET /api/history`: iOS reads watch history for the current API Key user.
- `GET /api/history/{videoPath}`: iOS reads one resume point.
- `POST /api/history`: iOS writes watch progress.

## Web Watch History Gap

The current Web history page reads `GET /api/history`, but the Web video player still saves progress to localStorage key `bililive_play_history`. To sync Web history with iOS, the Web player should call:

```http
POST /api/history
Content-Type: application/json

{
  "video_path": "抖音/主播/video.flv",
  "video_name": "video.flv",
  "position_seconds": 123.0,
  "duration_seconds": 456.0
}
```

Call this on the same cadence as the local progress save, and also on pause / close / seek completion.
