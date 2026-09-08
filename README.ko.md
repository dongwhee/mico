# mico

[English](README.md)

**mico는 Claude Code를 설정해 두고 물러난다.** `mico install`은 측정을 근거로 고른
한 가지 구성 — 전문 서브에이전트 6개, 비용 관련 전역 설정 3개, 사용자 호출 스킬 4개,
결정적 git 안전 훅 — 을 `~/.claude`에 설치한다. 그 다음부터는 평소대로 `claude`를
실행해서 일하면 된다. 감싸는 래퍼도, 상주 프로세스도, 따로 띄울 것도 없다.

이 기본값은 취향이 아니라 측정 결과다. mico에는 `mico orch`도 함께 들어 있다.
Claude Code를 *plan-only 오케스트레이터* — 파일을 직접 편집할 수 없고 모든 변경을
서브에이전트에 위임하는 세션 — 로 띄우는 런처다. 일반적인 3파일 과제에서 같은 결과를
내는 데 플레인 세션의 3~5배가 들었고([아래 수치](#플레인-세션이-기본인-이유)),
그래서 옵트인이다. 마지막 절이 그럼에도 값어치를 하는 상황에 대한 가이드다.

## 빠른 시작

```bash
git clone https://github.com/dongwhee/mico.git
cd mico
./bin/mico install
claude          # 설정은 전역이다. 그냥 쓰면 된다
```

`install`은 심볼릭 링크로 동작하므로 클론한 `mico/` 폴더는 지우거나 옮기지 말 것.

## `install`이 설치하는 것

심볼릭 링크:

| 링크 | 대상 |
|---|---|
| `~/.local/bin/mico` | `bin/mico` |
| `~/.claude/agents/*.md` (6개) | `agents/` |
| `~/.claude/skills/plan-file` | `skills/plan-file/` |
| `~/.claude/skills/review-loop` | `skills/review-loop/` |
| `~/.claude/skills/advisor-fable` | `skills/advisor-fable/` |
| `~/.claude/skills/codex-delegate` | `skills/codex-delegate/` |
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

### 전문 서브에이전트 6개

`implementer`(Sonnet), `code-investigator`(Sonnet, 1M, 프로젝트별 메모리),
`advisor`(Opus, xhigh, 1M), `web-researcher`(Sonnet), `git-runner`(Sonnet),
`lightweight-runner`(Haiku). 평범한 세션에서 Claude가 필요하다고 판단하면 위임한다.
각 설명문은 언제 쓰고 언제 쓰지 않는지를 말하고, "use proactively" 같은 호출 유도
문구는 의도적으로 넣지 않았다 — 측정에서 서브에이전트가 많은 세션이 사용량의 가장 큰
단일 요인이었다.

### 사용자 호출 스킬 4개

모두 슬래시 명령을 직접 입력해야 실행된다. Claude가 스스로 호출할 수 없으므로
(`disable-model-invocation`), 부르지 않는 한 비용이 슬그머니 들어오지 않는다:

- **`/plan-file <topic>`** — `.mico/plans/<topic>.md`를 작성·갱신한다: 목표, 검증
  명령이 붙은 체크 가능한 단계, 단계별 한 줄 로그, 노트. 끝나면 archive로 옮긴다.
  여러 단계나 여러 세션에 걸치는 작업용.
- **`/review-loop [목표 또는 플랜 경로]`** — 끝난 작업의 제한된 적대적 검증: Opus의
  읽기 전용 `code-investigator`가 목표 달성을 반박하려 시도하고, 분류, 수정, 변경
  hunk 범위의 재검토, 최대 3회, 두 판정을 모두 보고한다. 벤치마크 과제에서 이 패스
  한 번이 구현과 비슷한 비용이 들었기 때문에 옵트인이다.
- **`/advisor-fable [질문]`** — `advisor` 상담 한 건을 기본 Opus 대신 Fable로
  실행한다. 새 컨텍스트에서 나오는 독립적인 second opinion이며, 작업 *전*의
  설계·접근 결정용이다 — 끝난 diff를 사후 검토하는 용도가 아니다.
- **`/codex-delegate`** — 자족적인 작업 단위(구현+빌드+테스트, 또는 리뷰)를 Codex
  CLI의 샌드박스에 넘겨서, 원시 빌드 로그 대신 작은 판정 파일만 돌려받는다.
  `codex` CLI가 필요하다.

`/plan-file`과 `/review-loop`는 오케스트레이터 프롬프트에서 떼어낸 두 절차다. 즉
`mico orch`에서 플레인 세션 가격으로 가져올 만한 부분이다.

### git 안전 훅

`scripts/git-guard.sh`는 보통 CLAUDE.md에 권고문으로만 남는 git 규칙을 강제로 바꾼다.

- **차단** — 일괄 스테이징: `git add`에 `-A`/`--all`/`.`을 준 형태, 그리고
  `git commit -a`. 모델에게 경로를 명시해 스테이징하라고 알린다.
- **먼저 물음** — 되돌리기 어려운 작업: `git reset --hard`, `git push --force` /
  `-f` / `--force-with-lease`, `git clean -f`, `git branch -D`, `git stash
  drop|clear`. 대화형 세션에서는 auto 모드라도 권한 프롬프트가 뜨고, 아무도 답할 수
  없는 헤드리스(`-p`) 세션에서는 거부된다.

인용 문자열은 무시하고(커밋 메시지가 차단 대상 명령을 인용할 수 있다), 셸 세그먼트의
*시작*에 있는 명령만 검사하므로 `echo git add ...`는 git 명령이 아니고
`cd repo && git add ...`는 git 명령이다. 그 외는 모두 허용한다.

## 요구사항

- **`claude` CLI** (Claude Code) — 필수.
- **`jq`** — 설정 병합과 훅 두 개에 필수. 없으면 `install`은 직접 추가할 설정을
  출력만 하고, git 훅은 전부 허용하며, 오케스트레이터 가드는 *모든* 직접 편집을 막는다.
  설치: macOS `brew install jq` · Debian/Ubuntu `sudo apt install jq` ·
  Fedora `sudo dnf install jq`.
- **`~/.local/bin`이 PATH에 포함** — `mico` 명령을 바로 쓰기 위해.
- **`codex` CLI** — `/codex-delegate`와 `mico orch --impl codex`에만 필요 (선택).

## 설치 / 업데이트 / 제거

```bash
mico update      # 저장소 git pull (심볼릭 링크라 변경사항이 자동 반영)
mico uninstall   # 링크와 훅 제거, 관리 설정 키 복원
```

## 플레인 세션이 기본인 이유

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

## `mico orch` — 선택적 오케스트레이터 모드

### 무엇인가

오케스트레이터 세션에서 메인 Claude는 **코드를 편집할 수 없다.** 세션 범위 PreToolUse
훅이 짧은 예외 목록(모든 `*.md`, `.mico/plans/` 아래 플랜 문서, 자신의 메모리 문서,
`.mico/reports/`의 보고자료, 세션 scratchpad) 밖의 `Edit`/`Write`/`NotebookEdit`을
막는다. 따라서 모든 코드 변경은 명세로 적어 전문 서브에이전트에 넘겨야 하고, 그
에이전트가 수행과 검증을 함께 한다. 그 주위로 세션은:

- 작업을 플랜 파일 `.mico/plans/<topic>.md`에 담는다 — 목표, 단계, 단계별 검증 명령,
  로그 (템플릿과 규칙은 `prompts/orchestrator-prompt.md`);
- 최대 3회로 제한된 `code-investigator` 적대적 검증으로 끝난다;
- 안전한 git(`status`/`diff`/`log`/`add`/`commit`/`stash`/`fetch`/`pull`)은 프롬프트
  없이 실행하고, 파괴적 git은 계속 물어본다;
- `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`을 설정해 전문 에이전트의 재위임을 막는다;
- 다음 행동을 예고만 하고 끝난 턴을 `.mico/intent-turn-log.jsonl`에 기록한다
  (관찰 전용 — 아무것도 막지 않는다).

이 중 전역인 것은 없다. 훅과 권한은 `--settings`로 그 세션 하나에만 주입되고, 나머지
Claude Code 설정은 건드리지 않는다.

### 어떤 상황에 맞나

- **직접 편집이 권고가 아니라 물리적으로 불가능해야 할 때.** 차단이 훅이라 세션이
  어떻게 흘러가도 유지된다. 검토 없는 직접 편집의 대가가 큰 저장소라면 값을 한다.
- **몇 시간짜리 자율 실행을 지켜보지 않을 때.** 플랜 파일이 무엇을 시도했고 각 단계를
  어떻게 검증했는지의 감사 추적이 되고, 제한된 검증 루프가 "다 된 것 같다"는 모델
  자체 판단에 기대지 않는 정지 조건이 된다.
- **컨텍스트가 무겁거나 병렬화되는 작업** — 여러 파일에 걸친 조사, 또는 동시에 전문
  에이전트로 펼칠 수 있는 독립적인 하위 작업 여러 개. 멀티 에이전트 오버헤드가 실제로
  값을 하는 형태다.
- **검증 패스를 실행의 일부로 두고 싶을 때** — 끝에 가서 기억해 내 호출하는 것이 아니라.

### 어떤 상황에 맞지 않나

- **파일 몇 개짜리 일상 작업.** 위 표대로 같은 결과에 비용은 몇 배, 소요 시간은 약
  4~5배다. 게다가 약속한 "가벼운 메인 컨텍스트"도 실현되지 않았다.
- **턴마다 직접 방향을 잡는 작업.** 명세를 적어 위임하는 왕복이 변경마다 지연을 더하고,
  대화형 작업을 빠르게 만드는 직접 편집을 잃는다.
- **원한 것이 사실은 규율일 때.** 플레인 세션에 `/plan-file`과 `/review-loop`를 더하면
  플랜 파일과 적대적 검증을 플레인 세션 가격으로 얻는다. 여기서 시작하고, 가드 자체가
  목적일 때만 `mico orch`로 간다.

### 실행

```bash
mico orch                          # Opus 오케스트레이터 1M 컨텍스트; Sonnet implementer; Opus xhigh advisor
mico orch --orch sonnet            # 가벼운 오케스트레이터: Sonnet (역시 1M)
mico orch --orch fable --effort medium
mico orch --no-1m                  # 1M 대신 200k 컨텍스트
mico orch --advisor fable          # advisor agent를 Opus 대신 Fable로
mico orch --impl opus              # 모든 implementer 위임을 Opus로 강제
mico orch --impl codex             # 구현을 codex-delegate(build 모드)로 라우팅
mico orch --codex-effort high      # codex 추론 강도 (--impl codex에서 기본 xhigh)
mico orch --continue               # 인식하지 못한 인자는 claude로 그대로 전달
mico orch --help                   # 전체 옵션
```

`--advisor fable`은 세션 전체에 적용되고, `/advisor-fable [질문]`은 상담 한 건만
Fable로 실행하며 플레인 세션에서도 쓸 수 있다. Agent 툴의 `model` 오버라이드는 세션의
컨텍스트 창 접미사를 상속하므로, 기본 `opus[1m]` 세션에서는 상담도 큰 창을 유지하고
`--no-1m` 세션에서만 200k로 떨어진다.

### `mico setup`

```bash
mico setup      # 현재 프로젝트 문서를 오케스트레이터 컨벤션에 맞춤
```

현재 프로젝트에서 헤드리스 Claude를 띄워 CLAUDE.md에 프로젝트 자체 플랜과
`.mico/plans/`를 구분하는 노트를 추가하고, `.mico/`를 gitignore 처리하고, 다른 문서의
충돌은 수정 없이 리포트한다. 대화형으로 실행하면 이 프로젝트에 `code-review-graph`
(로컬 코드 인덱스 MCP 서버)를 설치·빌드할지도 물어본다 — 새로 추가된 프로젝트 MCP
서버는 다음 대화형 실행에서 한 번 승인해야 한다. 실제로 `mico orch`를 쓰는
프로젝트에서만 필요하다.
