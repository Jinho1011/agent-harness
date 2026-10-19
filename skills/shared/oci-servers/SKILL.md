---
name: oci-servers
description: Operate the user's existing Oracle Cloud A1 and Micro servers from the jjh-server management host over Tailscale and SSH. Use for requests about 오라클 서버, OCI A1, or OCI Micro, including remote commands, deployments, files, services, and troubleshooting; not for unrelated Oracle accounts or databases.
---

# OCI 서버 작업

기존 두 서버에서 사용자가 요청한 작업을 실행한다. 접속 구성을 다시 설치하는 스킬이 아니다.

## 대상과 접속

관리 서버의 Tailscale 이름은 `jjh-server`다. OS hostname과는 다를 수 있다.
이 관리 서버에 설정된 SSH 별칭을 사용한다. 공인 IP나 임시 첨부 키 경로에 의존하지 않는다.

| 사용자 표현 | SSH 별칭 | 원격 hostname | 아키텍처 |
|---|---|---|---|
| A1, ARM 서버 | `oci-a1` | `instance-20261018-0230` | `aarch64` / Docker `linux/arm64` |
| Micro, 마이크로 서버 | `oci-micro` | `instance-20261008-0121` | `x86_64` / Docker `linux/amd64` |

두 서버는 Oracle Linux 9이며 SSH 사용자는 `opc`다. 관리자 명령은 원격에서 `sudo -n`으로 실행한다.
사용자가 말하는 관리 서버 자체와 두 원격 서버를 구분한다. 문맥으로 작업 대상을 정할 수 없으면 변경 전에 확인한다.

최초 작업 시 대상 확인은 짧게 한다. 단순 상태 질문에는 필요한 명령만 실행한다.

```sh
ssh -o BatchMode=yes -o ConnectTimeout=10 oci-a1 'hostname; uname -m'
ssh -o BatchMode=yes -o ConnectTimeout=10 oci-micro 'hostname; uname -m'
```

예상과 다른 호스트나 호스트 키가 나오면 대상을 확인한다. `StrictHostKeyChecking`을 끄거나 `known_hosts` 항목을 자동 삭제하지 않는다.
다른 머신에서 이 스킬을 읽었더라도 같은 SSH 설정이 있다고 가정하지 않는다. 필요한 경우 `ssh -G <별칭>`으로 확인한다.

## 키 잠금과 연결 문제

서버별 개인키는 암호화되어 있고 관리 서버에만 보관한다.

| 대상 | 개인키 | Bitwarden 항목의 site |
|---|---|---|
| Micro | `~/.ssh/id_ed25519_oci_micro` | `ssh-oci-micro-jjh-server` |
| A1 | `~/.ssh/id_ed25519_oci_a1` | `ssh-oci-a1-jjh-server` |

SSH 설정의 `IdentityAgent`는 `~/.ssh/oci-agent.sock`을 사용한다.
사용자 서비스 `oci-ssh-agent.service`가 이 에이전트를 실행한다. 기본 GPG SSH 에이전트는 새 키 추가를 거부한 이력이 있어 사용하지 않는다.

관리 서버 재부팅 후에는 에이전트가 비어 있을 수 있다.

```sh
systemctl --user is-active oci-ssh-agent.service
SSH_AUTH_SOCK="$HOME/.ssh/oci-agent.sock" ssh-add -l
oci-ssh-unlock
```

`oci-ssh-unlock`은 두 키의 암호를 대화형으로 요청한다. 비대화형 작업에서는 사용 가능한 Bitwarden 연동의 `get_credential`로 위 site의 암호를 가져와 해당 에이전트에 키를 적재한다.
계정 연동이 필요하면 `web-account` 스킬을 참고한다. 암호나 개인키를 출력하거나 스킬, 명령행 인자, 평문 파일에 저장하지 않는다.
필요한 인증 수단이 없으면 막힌 단계를 설명한다. 암호화 해제나 공인 SSH 개방으로 우회하지 않는다.

접속 오류를 구분한다. 인증 실패는 키·에이전트, 이름 해석 실패는 SSH 설정·Tailscale DNS, 연결 거부나 시간 초과는 대상 서비스·네트워크를 먼저 확인한다.

## 원격 작업

사용자가 요청한 범위에서 원격 명령, 파일 전송, 서비스 관리와 배포를 진행한다. 일반 작업 때문에 SSH·키·방화벽·OCI 계정 설정을 다시 구성하지 않는다.
배포 전에 필요한 경우에만 대상 OS, 자원, 기존 서비스 구성을 확인한다. 관리 서버의 바이너리를 그대로 복사하지 말고 대상 아키텍처에 맞게 빌드하거나 이미지를 선택한다.
작업 후에는 해당 호스트에서 요청한 결과를 직접 검증하고 실행한 명령과 결과를 보고한다.

## 네트워크 설정을 바꿀 때만

현재 SSH 경로는 **Tailscale 위의 일반 OpenSSH**다. Tailscale SSH 기능을 켠 구성이 아니다.
두 서버의 firewalld에서 `tailscale0`은 `tailnet-ssh` 영역에 속하고 이 영역은 `ssh` 서비스를 허용한다. 공인 인터페이스의 `public` 영역에서는 `ssh`가 제거되어 있다.
비밀번호 로그인과 root 직접 로그인은 꺼져 있다. OCI 보안 목록은 초기 연결 작업에서 변경하지 않았다. 기존 OCI 키의 공개키는 복구용으로 남아 있다.

Oracle Linux의 별도 nftables/firewalld 규칙이 Tailscale의 iptables 허용 뒤에도 패킷을 거부할 수 있다.
실제로 `tailscale0` 영역을 지정하지 않고 `public`의 SSH만 제거했을 때 사설망 SSH도 끊겼다.

SSH 경로·방화벽을 변경하는 작업이라면 먼저 Tailscale 인터페이스의 허용을 확인한다. 기존 세션과 시간 제한 자동 복구를 확보한 뒤, **별도 새 SSH 연결**로 변경을 검증한다.
자동 복구 타이머는 `AccuracySec=1s` 등 실행 오차도 고려해 설정한다. 영구 설정을 다시 불러온 뒤에도 사설망 접속이 성공하는지 확인하고, 검증이 끝나면 복구 예약을 해제한다.
공인 SSH를 차단하는 요청이라면 관리 서버에서 공인 TCP/22의 차단 여부도 확인한다. 재부팅이나 다른 장치의 접근 차단은 그 작업에 필요한 경우에만 수행한다.
