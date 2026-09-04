# mico

[English](README.md)

Claude Code를 plan-only 오케스트레이터(기본 Opus, 1M 컨텍스트)로 띄우고, 실제 작업은 전문
서브에이전트(implementer·advisor·web-researcher·code-investigator·git-runner·lightweight-runner)에
위임하는 런처/설정 모음. 기본적으로 모든 작업은 Claude 모델로 처리되며, 구현은
`--impl codex`를 줄 때에 한해 Codex CLI(`codex-delegate` 스킬)로 라우팅된다.

Claude Code 토큰 사용량을 관리하기 위해 만들었다 — 메인 세션은 가볍게(계획·위임만) 유지하고, 무겁거나 노이즈가 큰 작업은 저렴한 서브에이전트로, 추론 effort는 에이전트별로 조절해 라우팅한다. 서브에이전트는 1단계까지만 허용되므로(mico가 `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` 기본값을 1로 설정 — 직접 export하면 덮어쓸 수 있다) 전문 에이전트가 다시 위임할 수 없다.

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
| `~/.claude/agents/*.md` (6개) | `agents/` |
| `~/.claude/skills/codex-delegate` | `skills/codex-delegate/` |
| `~/.claude/skills/advisor-fable` | `skills/advisor-fable/` |
| `~/.claude/scripts/codex-delegate.sh` | `scripts/codex-delegate.sh` |
| `~/.claude/scripts/orchestrator-guard.sh` | `scripts/orchestrator-guard.sh` |

같은 경로에 실제 파일이 이미 있으면 `~/.claude/backups/mico/`로 백업 후 링크한다
(`uninstall` 시 복원). 설치는 전역 `~/.claude/settings.json`을 건드리지 않는다 —
plan-only 가드 훅은 `mico` 실행 시 `--settings`로 그 세션에만 주입된다.

## 사용

```bash
mico                          # Opus 오케스트레이터 1M 컨텍스트 + Sonnet 5 implementer + Opus xhigh advisor agent
mico --orch sonnet            # 가벼운 오케스트레이터: Sonnet 5 (역시 1M)
mico --no-1m                  # 오케스트레이터를 200k 컨텍스트로 되돌림
mico --advisor fable          # advisor agent를 Opus 대신 Fable 5로 실행
mico --effort xhigh           # 오케스트레이터 effort 상향 (high가 모델 기본값, max도 유효)
mico --impl opus              # 모든 implementer 위임을 Opus로 강제
mico --impl codex             # 구현을 codex-delegate(build, xhigh)로 라우팅
mico --codex-effort high      # codex effort 오버라이드 (CODEX_DELEGATE_EFFORT)
mico --continue               # 나머지 인자는 claude로 그대로 전달
mico setup                    # 현재 프로젝트 폴더에서 headless Claude 실행 (아래 참고)
mico --help                   # 전체 옵션
```

`--advisor fable`은 세션 전체에 적용된다. 한 번만 쓰려면 세션 중에
`/advisor-fable [질문]`을 입력하면 된다 — 그 상담 한 건만 Opus 대신 Fable 5로 실행한다.
이 스킬은 사용자 전용(user-invocable only)이라 오케스트레이터가 스스로 Fable로 올릴 수 없고,
필요하다고 제안만 할 수 있다. 트레이드오프: Agent 툴의 `model` 오버라이드는 에이전트
frontmatter의 `opus[1m]`을 대체하므로, Fable 상담은 1M이 아니라 200k 컨텍스트로 돌아간다.

`mico setup`은 현재 프로젝트 폴더에서 headless Claude(`claude -p`)를 띄워 그 프로젝트의
문서를 mico 컨벤션에 맞춘다: CLAUDE.md에 (프로젝트 자체 플랜 vs 오케스트레이터의
`.mico/plans/`) 구분 노트 추가, `.gitignore`에 `.mico/` 추가, 그리고 다른 문서
(AGENTS.md·docs/·README)의 충돌은 수정 없이 요약으로 리포트한다. 멱등(idempotent)하며,
끝난 뒤 `jq`가 없으면 설치를 권고한다.

오케스트레이터는 plan-only다: 가드 훅이 몇 가지 예외를 뺀 모든 파일에 대해
Edit/Write/NotebookEdit을 막으므로, 코드는 분석·계획·위임만 한다 (`prompts/orchestrator-prompt.md`의 라우팅 테이블 참고).
단, 어떤 `.md` 파일이든 직접 편집할 수 있고, 보고자료도 직접 만들 수 있으며(아래 참고),
안전한 git 일부
(status/diff/log/add/commit/stash/fetch/pull/...)는 프롬프트 없이 바로 실행한다.
그 외 모든 파일 편집과 파괴적/외부로 나가는 git(push, reset --hard, force-push, rebase)은
여전히 서브에이전트에 위임한다 (공개 `git push`는 하니스가 추가로 게이트한다).

플랜·메모리 문서도 그 마크다운의 한 사례일 뿐이다: 오케스트레이터는
`<project>/.mico/plans/<topic>.md` 플랜 문서와 자신의 메모리 문서
(`~/.claude/projects/<project>/memory/`)를 직접 Write/Edit할 수 있다. 플랜
컨벤션은 최소 frontmatter(`goal`/`status`/`created`) + 체크 가능한 `## Steps`이며, 루트
디렉터리에는 진행 중인 플랜만 두고 끝난 플랜은 `.mico/plans/archive/`로 옮긴다 — 따라서
디렉터리 목록 자체가 활성 플랜 인덱스다 (INDEX 파일도 grep도 필요 없음). 자세한 내용은
`prompts/orchestrator-prompt.md`의 "Plan files" 섹션 참고.

보고자료(report deliverable)가 나머지 예외다. 감사 결과·비교표·다이어그램 같은 HTML 페이지를
사용자에게 건네는 일은 구현이 아니라 보고이므로, `implementer`를 한 번 태우는 대신
오케스트레이터가 직접 작성한다. 열려 있는 위치는 두 곳이고 확장자는 가리지 않는다
(`.html`/`.css`/`.js`/데이터 파일 모두):

- **세션 scratchpad** — 시스템 임시 디렉터리(`$TMPDIR`, `/tmp`, `/private/tmp`,
  `/var/folders`, `/private/var/folders`) 아래의 `scratchpad/` 디렉터리로, Claude Code가 세션별 임시 파일을
  두는 곳이다. 내장 `Artifact` 도구로 발행해 링크로 건네는 기본 경로. 이름만
  `scratchpad/`인 프로젝트 내부 디렉터리는 예외가 *아니다* — 판정 기준이 작업
  디렉터리가 아니라 임시 루트라, `mico`를 리포의 어느 하위 폴더에서 띄웠든 동일하다.
- **`.mico/reports/`** — 파일을 프로젝트 디스크에 남기고 싶을 때. `mico setup`이 이미
  `.mico/`를 gitignore 처리하므로, 일부러 추가하지 않는 한 리포 히스토리에는 남지 않는다.

그 외에는 그대로 `implementer` 몫이다 — 제품의 일부로 나가는 HTML은 여전히 코드다.
`jq` 의존성도 유의: `jq`가 없으면 가드가 폴백으로 *모든* 직접 편집을 막으므로 보고자료도
쓸 수 없다.

## 업데이트 / 제거

```bash
mico update      # 저장소 git pull (심볼릭 링크라 변경사항이 자동 반영)
mico uninstall   # 링크 제거, 백업 복원
```
