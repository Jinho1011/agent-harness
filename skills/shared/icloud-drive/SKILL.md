---
name: icloud-drive
description: Use iCloud Drive from this Ubuntu server through the existing rclone remote `icloud:`. Use when the user mentions iCloud, 아이클라우드, or iCloud Drive and wants to upload, download, list, or back up files, or when the iCloud login has expired and needs a new 2FA code; not for iCloud Photos downloads, calendar, contacts, or mail.
---

# iCloud Drive (rclone)

이 서버에는 iCloud Drive가 rclone remote `icloud:`로 이미 연결되어 있다. 새로 설치하거나 로그인하지 않고 바로 쓴다.

## 전제

- rclone은 `~/.local/bin/rclone`(v1.76 이상)을 쓴다. 시스템 `/usr/bin/rclone`(v1.61)은 iCloud 백엔드가 없으므로 PATH 우선순위를 확인한다.
- 설정은 `~/.config/rclone/rclone.conf`(권한 600)에 있다. 이 파일은 출력, 복사, 커밋하지 않는다. 비밀번호와 세션 값이 들어 있다.
- 업로드와 다운로드는 검증되었다(테스트 파일 sha256 일치).

## 자주 쓰는 명령

```bash
rclone lsd icloud:                         # 최상위 폴더 (연결 확인)
rclone ls icloud:폴더                      # 파일 목록
rclone copy /서버/경로 icloud:폴더 -v      # 서버 -> iCloud (iCloud 쪽 파일을 지우지 않음)
rclone copy icloud:폴더 /서버/경로         # iCloud -> 서버
```

- 기본은 `copy`를 쓴다. `sync`와 `purge`, `delete`는 대상 파일을 지우므로 사용자가 요청하거나 확인한 경우에만 쓴다.
- 업로드 후에는 `rclone ls`나 `rclone check`로 올라갔는지 확인한다.
- 속도가 느리다(작은 파일 하나에 수 초). 큰 작업은 백그라운드로 돌리고 진행 상황을 보고한다.
- 사용자의 기존 iCloud 폴더(Documents, Desktop, pictures 등)에는 요청 없이 쓰거나 지우지 않는다. 테스트는 `_rclone-upload-test` 같은 새 폴더에서 하고 끝나면 지운다.

## 로그인 만료 시 (약 30일마다)

증상: `rclone lsd icloud:`가 인증, 401, 423, 2FA 오류를 낸다.

1. 사용자에게 곧 폰에 6자리 코드가 뜬다고 알린다(승인 팝업은 "허용"을 눌러야 코드가 보인다).
2. 로그인을 시작한다. 2FA 질문 JSON이 나오고 State가 `2fa_do`이면 코드 입력 대기 상태다.
   ```bash
   rclone config update icloud --non-interactive
   ```
3. 사용자가 알려준 코드로 이어간다.
   ```bash
   rclone config update icloud --continue --state 2fa_do --result 123456 --non-interactive
   rclone lsd icloud:     # 확인
   ```

함정:
- `rclone config create`나 스크립트의 대화형 입력은 질문에 기본값(빈 값)을 넣어 `2FA codes can't be blank`로 실패한다. 반드시 `--non-interactive`와 `--continue`를 쓴다.
- 비밀번호가 바뀌었거나 설정이 깨졌으면 `rclone config update icloud apple_id=... password=...`로 갱신한다. 비밀번호는 사용자가 직접 입력하게 하고, 채팅에 요청하기 전에 방식을 설명한다.
- 코드는 몇 분 안에 만료된다. 실패하면 3번을 다시 하지 말고 2번부터 새로 시작한다.

## 조건과 제한

- 아이폰의 "웹에서 iCloud 데이터 접근"이 켜져 있어야 한다. 고급 데이터 보호(ADP)를 켠 계정은 실패할 수 있다.
- 앱 암호는 쓸 수 없다. 실제 Apple ID 비밀번호와 2FA가 필요하다.
- 사진 라이브러리 백업은 rclone이 아니라 `icloudpd` 계열이 맞다. 서버에는 아직 설치하지 않았다.
- 정기 업로드가 필요하면 user systemd 서비스와 타이머를 만들고 `10-on-failure.conf`(OnFailure 알림)를 붙인다.
