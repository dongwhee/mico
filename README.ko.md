# mico

[English](README.md)

Claude Code 설정 유틸리티. `mico install`은 측정을 근거로 고른 한 가지 구성 —
전문 서브에이전트 6개, 비용 관련 전역 설정 3개, 결정적 git 안전 훅 — 을 설치해서
**플레인** Claude Code 세션이 기본 작업 방식이 되게 한다. 원래의 plan-only
오케스트레이터는 `mico orch`로 남아 있으며, 그 비용이 정당화되는 경우에만 쓴다.

## `install`이 하는 일

심볼릭 링크 (클론한 `mico/` 폴더는 지우거나 옮기지 말 것):

| 링크 | 대상 |
|---|---|
| `~/.local/bin/mico` | `bin/mico` |
| `~/.claude/agents/*.md` (6개) | `agents/` |
| `~/.claude/skills/codex-delegate` | `skills/codex-delegate/` |
| `~/.claude/skills/advisor-fable` | `skills/advisor-fable/` |
| `~/.claude/skills/plan-file` | `skills/plan-file/` |
| `~/.claude/skills/review-loop` | `skills/review-loop/` |
| `~/.claude/scripts/git-guard.sh` | `scripts/git-guard.sh` |
| `~/.claude/scripts/orchestrator-guard.sh` | `scripts/orchestrator-guard.sh` |
| `~/.claude/scripts/codex-delegate.sh` | `scripts/codex-delegate.sh` |

`~/.claude/settings.json`에 병합하는 관리 키 (첫 병합 전에 파일 전체를
`~/.claude/backups/mico/settings.json`으로 한 번 백업하고, 그 외 항목은 건드리지
않으며, `install`을 다시 실행해도 결과는 같다):

| 키 | 값 | 이유 |
|---|---|---|
| `model` | `opus[1m]` | 아래 벤치마크 과제를 다른 모델과 같은 품질로 끝낸 가장 싼 현행 모델. |
| `autoCompactWindow` | `300000` | 측정된 사용량의 약 74%가 150k 초과 컨텍스트에서 나왔고, 1M 모델은 그대로 두면 압축이 일어나지 않는다. 압축이 너무 잦으면 `400000`으로 올린다. |
| `env.CLAUDE_CODE_SUBAGENT_MODEL` | `sonnet` | 내장 서브에이전트(Explore, Plan, general-purpose)가 Opus를 상속하지 않고 Sonnet으로 돈다. 프론트매터에 `model`이 있는 에이전트는 그 값을 유지한다 — 프론트매터가 환경변수보다 우선. |
| `hooks.PreToolUse` (matcher `Bash`) | `scripts/git-guard.sh` | 아래 참고. |

`uninstall`은 링크와 훅 항목을 제거하고, 관리 키를 백업에 있던 값으로 되돌린다
(백업에 없던 키는 삭제).

### 서브에이전트 6개

`implementer`(Sonnet), `code-investigator`(Sonnet, 1M, 프로젝트별 메모리),
`advisor`(Opus, xhigh, 1M), `web-researcher`(Sonnet), `git-runner`(Sonnet),
`lightweight-runner`(Haiku). 플레인 세션에서 Claude가 필요하다고 판단하면 위임한다.
각 설명문은 언제 쓰고 언제 쓰지 않는지를 말하고, "use proactively" 같은 호출 유도
문구는 의도적으로 넣지 않았다 — 측정에서 서브에이전트가 많은 세션이 사용량의 가장
큰 단일 요인이었다.

### 옵트인 스킬 두 개

오케스트레이터 없이도 남길 가치가 있는 두 절차를 플레인 세션에서 부를 수 있는
사용자 호출 스킬로 제공한다 (Claude가 스스로 호출할 수 없으므로, 부르지 않는 한 그
비용이 다시 들어오지 않는다):

- `/plan-file <topic>` — `.mico/plans/<topic>.md`를 작성·갱신한다: 목표, 검증 명령이
  붙은 체크 가능한 단계, 단계별 한 줄 로그, 노트. 끝나면 archive로 옮긴다. 여러 단계나
  여러 세션에 걸치는 작업용.
- `/review-loop [목표 또는 플랜 경로]` — 끝난 작업의 제한된 적대적 검증: Opus의
  읽기 전용 `code-investigator`가 목표 달성을 반박하려 시도하고, 분류, 수정, 변경
  hunk 범위의 재검토, 최대 3회, 두 판정을 모두 보고한다. 벤치마크 과제에서 이 패스
  한 번이 구현과 비슷한 비용이 들었기 때문에 옵트인이다.

### git 안전 훅

`scripts/git-guard.sh`는 보통 CLAUDE.md에 권고문으로만 남는 git 규칙을 강제로 바꾼다.

- **차단** — 일괄 스테이징: `git add -A`, `git add --all`, `git add .`,
  `git commit -a`. 모델에게 경로를 명시해 스테이징하라고 알린다.
- **먼저 물음** — 되돌리기 어려운 작업: `git reset --hard`, `git push --force` /
  `-f` / `--force-with-lease`, `git clean -f`, `git branch -D`, `git stash
  drop|clear`. 대화형 세션에서는 auto 모드라도 권한 프롬프트가 뜨고, 아무도 답할 수
  없는 헤드리스(`-p`) 세션에서는 거부된다.

인용 문자열은 무시하고(커밋 메시지에 "git add -A"가 들어갈 수 있다), 셸 세그먼트의
*시작*에 있는 명령만 검사하므로 `echo git add -A`는 git 명령이 아니고 `cd repo &&
git add -A`는 git 명령이다. 그 외는 모두 허용한다.

## 요구사항

- **`claude` CLI** (Claude Code) — 필수.
- **`jq`** — 설정 병합과 훅 두 개에 필수. 없으면 `install`은 직접 추가할 설정을
  출력만 하고, git 훅은 전부 허용하며, 오케스트레이터 가드는 *모든* 직접 편집을 막는다.
  설치: macOS `brew install jq` · Debian/Ubuntu `sudo apt install jq` ·
  Fedora `sudo dnf install jq`.
- **`~/.local/bin`이 PATH에 포함** — `mico` 명령을 바로 쓰기 위해.
- **`codex` CLI** — `mico orch --impl codex`에만 필요 (선택).

## 설치 / 업데이트 / 제거

```bash
git clone https://github.com/dongwhee/mico.git
cd mico
./bin/mico install

mico update      # 저장소 git pull (심볼릭 링크라 변경사항이 자동 반영)
mico uninstall   # 링크와 훅 제거, 관리 설정 키 복원
```

`install` 뒤에는 그냥 `claude`를 실행하면 된다. 따로 띄울 것이 없다.

## 플레인 Claude Code가 기본인 이유

같은 3파일 백엔드 과제(실제 FastAPI 저장소에서 YAML 파서에 입력 검증과 누락된
테스트 추가)를 구성별로 한 번씩, 헤드리스로, 각자 별도 git worktree에서 실행하고
테스트는 프로젝트의 CI 컨테이너에서 돌렸다. 네 구성 모두 올바른 구현을 내고 테스트를
통과했다.

| 구성 | API 비용(추정) | 소요 | API 호출 (메인 / 서브) | 메인 컨텍스트 최대 |
|---|---|---|---|---|
| 플레인 Claude Code, Opus 5 | $0.71 | 142초 | 13 / 0 | 44k |
| 플레인 Claude Code, Fable 5.1 | $1.04 | 154초 | 6 / 0 | 43k |
| `mico orch --orch fable --effort medium` | $2.03 | 575초 | 11 / 38 | 50k |
| `mico orch` (Opus 오케스트레이터, Sonnet 구현자) | $3.28 | 702초 | 18 / 62 | 60k |

오케스트레이터가 약속한 "가벼운 메인 컨텍스트"는 나타나지 않았다. 메인 컨텍스트
최대치가 플레인보다 오히려 *컸고*, 가장 큰 비용 항목은 Opus 검증 패스였다. 멀티
에이전트 구성은 단일 에이전트의 3~10배를 쓰며 컨텍스트가 무겁거나 병렬인 작업에서만
값어치를 한다는 Anthropic 자체 가이드와 일치한다. 작은 과제 하나를 한 번씩 돌린
수치이므로 방향으로 읽고 정밀도로 읽지는 말 것.

## `mico orch` — plan-only 오케스트레이터

```bash
mico orch                          # Opus 오케스트레이터 1M 컨텍스트; Sonnet implementer; Opus xhigh advisor
mico orch --orch sonnet            # 가벼운 오케스트레이터: Sonnet (역시 1M)
mico orch --orch fable --effort medium
mico orch --no-1m                  # 1M 대신 200k 컨텍스트
mico orch --advisor fable          # advisor agent를 Opus 대신 Fable로
mico orch --impl opus              # 모든 implementer 위임을 Opus로 강제
mico orch --impl codex             # 구현을 codex-delegate(build, xhigh)로 라우팅
mico orch --continue               # 나머지 인자는 claude로 그대로 전달
mico orch --help                   # 전체 옵션
mico setup                         # 현재 프로젝트 문서를 오케스트레이터 컨벤션에 맞춤
```

Claude가 오케스트레이터로 돈다: 세션 범위 PreToolUse 훅이 짧은 예외 목록(모든
`*.md`, `.mico/plans/` 아래 플랜 문서, 자신의 메모리 문서, `.mico/reports/` 또는
세션 scratchpad의 보고자료) 밖의 Edit/Write/NotebookEdit을 막고, 안전 git 허용
목록으로 status/diff/log/add/commit/stash/fetch/pull은 프롬프트 없이 실행하며,
관찰 전용 Stop 프로브가 다음 행동을 예고만 하고 끝난 턴을
`.mico/intent-turn-log.jsonl`에 기록하고, `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`로
전문 에이전트의 재위임을 막는다. 작업은 플랜 파일(`.mico/plans/<topic>.md`, 템플릿과
규칙은 `prompts/orchestrator-prompt.md`)을 거치고, 최대 3회로 제한된 `code-investigator`
적대적 검증으로 끝난다.

편집을 물리적으로 막아야 하거나, 여러 시간짜리 자율 실행에 플랜 파일의 감사 추적과
제한된 검증 루프가 필요할 때 쓴다. 일상 작업에서 쓰지 않을 이유는 위 표다.

`--advisor fable`은 세션 전체에 적용되고, `/advisor-fable [질문]`은 상담 한 건만
Fable로 실행한다. Agent 툴의 `model` 오버라이드는 세션의 컨텍스트 창 접미사를
상속하므로, 기본 `opus[1m]` 세션에서는 상담도 큰 창을 유지하고 `--no-1m` 세션에서만
200k로 떨어진다.

`mico setup`은 현재 프로젝트에서 헤드리스 Claude를 띄워 CLAUDE.md에 프로젝트 자체
플랜과 `.mico/plans/`를 구분하는 노트를 추가하고, `.mico/`를 gitignore 처리하고,
다른 문서의 충돌은 수정 없이 리포트한다. 실제로 `mico orch`를 쓰는 프로젝트에서만
필요하다.
