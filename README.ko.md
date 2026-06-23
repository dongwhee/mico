# mico

[English](README.md)

Claude Code를 plan-only 오케스트레이터(기본 Opus)로 띄우고, 실제 작업은 전문
서브에이전트(implementer·web-researcher·code-investigator·git-runner·lightweight-runner)와
Codex CLI(`codex-delegate` 스킬)에 위임하는 런처/설정 모음.

Claude Code 토큰 사용량을 관리하기 위해 만들었다 — 메인 세션은 가볍게(계획·위임만) 유지하고, 무겁거나 노이즈가 큰 작업은 저렴한 서브에이전트로, 추론 effort는 작업에 맞게 조절해 라우팅한다.

## 요구사항

- **`claude` CLI** (Claude Code) — 필수.
- **`jq`** — 권장. 없으면 오케스트레이터 가드가 폴백으로 *모든* 직접 편집을 막아,
  플랜/메모리 문서조차 오케스트레이터가 직접 고치지 못하고 전부 위임하게 된다.
  설치: macOS `brew install jq` · Debian/Ubuntu `sudo apt install jq` ·
  Fedora `sudo dnf install jq` (또는 사용하는 패키지 매니저).
- **`~/.local/bin`이 PATH에 포함** — `mico` 명령을 바로 쓰기 위해.
- **`codex` CLI** — `--impl codex`(코덱스 위임)를 쓸 때만 필요 (선택).

## 설치

```bash
git clone https://github.com/dongwhee/mico.git
cd mico
./bin/mico install
```

`install`은 심볼릭 링크만 만든다. 클론한 `mico/` 폴더는 **지우거나 옮기지 말 것** —
링크가 이 폴더를 가리킨다.

| 링크 | 대상 |
|---|---|
| `~/.local/bin/mico` | `bin/mico` |
| `~/.claude/agents/*.md` (5개) | `agents/` |
| `~/.claude/skills/codex-delegate` | `skills/codex-delegate/` |
| `~/.claude/scripts/codex-delegate.sh` | `scripts/codex-delegate.sh` |
| `~/.claude/scripts/orchestrator-guard.sh` | `scripts/orchestrator-guard.sh` |

같은 경로에 실제 파일이 이미 있으면 `~/.claude/backups/mico/`로 백업 후 링크한다
(`uninstall` 시 복원). 설치는 전역 `~/.claude/settings.json`을 건드리지 않는다 —
plan-only 가드 훅은 `mico` 실행 시 `--settings`로 그 세션에만 주입된다.

## 사용

```bash
mico                          # Opus 오케스트레이터(effort xhigh + Opus advisor) + implementer(기본 Opus, 단순 spec은 Sonnet)
mico --impl codex             # 구현을 codex-delegate(build, xhigh)로 라우팅
mico --codex-effort high      # codex effort 오버라이드 (CODEX_DELEGATE_EFFORT)
mico --continue               # 나머지 인자는 claude로 그대로 전달
mico setup                    # 현재 프로젝트 폴더에서 headless Claude 실행 (아래 참고)
mico --help                   # 전체 옵션
```

`mico setup`은 현재 프로젝트 폴더에서 headless Claude(`claude -p`)를 띄워 그 프로젝트의
문서를 mico 컨벤션에 맞춘다: CLAUDE.md에 (프로젝트 자체 플랜 vs 오케스트레이터의
`.mico/plans/`) 구분 노트 추가, `.gitignore`에 `.mico/` 추가, 그리고 다른 문서
(AGENTS.md·docs/·README)의 충돌은 수정 없이 요약으로 리포트한다. 멱등(idempotent)하며,
끝난 뒤 `jq`가 없으면 설치를 권고한다.

오케스트레이터는 plan-only다: 가드 훅이 비(非)마크다운 파일에 대한 Edit/Write/NotebookEdit을
막으므로, 코드는 분석·계획·위임만 한다 (`prompts/orchestrator-prompt.md`의 라우팅 테이블 참고).
단, 어떤 `.md` 파일이든 직접 편집할 수 있고, 안전한 git 일부
(status/diff/log/add/commit/stash/fetch/pull/...)는 프롬프트 없이 바로 실행한다.
비마크다운 코드 편집과 파괴적/외부로 나가는 git(push, reset --hard, force-push, rebase)은
여전히 서브에이전트에 위임한다 (공개 `git push`는 하니스가 추가로 게이트한다).

플랜·메모리 문서도 그 마크다운의 한 사례일 뿐이다: 오케스트레이터는
`<project>/.mico/plans/<topic>.md` 플랜 문서와 자신의 메모리 문서
(`~/.claude/projects/<project>/memory/`)를 직접 Write/Edit할 수 있다. 플랜
컨벤션은 최소 frontmatter(`goal`/`status`/`created`) + 체크 가능한 `## Steps`이며, 루트
디렉터리에는 진행 중인 플랜만 두고 끝난 플랜은 `.mico/plans/archive/`로 옮긴다 — 따라서
디렉터리 목록 자체가 활성 플랜 인덱스다 (INDEX 파일도 grep도 필요 없음). 자세한 내용은
`prompts/orchestrator-prompt.md`의 "Plan files" 섹션 참고.

## 업데이트 / 제거

```bash
mico update      # 저장소 git pull (심볼릭 링크라 변경사항이 자동 반영)
mico uninstall   # 링크 제거, 백업 복원
```
