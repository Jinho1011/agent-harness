# 사업 구상용 Skills / MCP 조사

조사 기준일: 2026-10-07. 최근 2주 판정 구간: **2026-09-23~2026-10-07 UTC**. GitHub stars는 API 조회 당시 값이며 변동한다. 조건은 개별 스킬의 별점이 아니라 **스킬/MCP를 배포하는 저장소의 stars ≥ 2,000**, 그리고 저장소 유지관리자의 실제 활동으로 해석했다. 개별 스킬 파일이 2주 이내 수정됐다는 의미는 아니다.

검증은 `updated_at`/`pushed_at` 대신 PR 상세 API의 `author_association`, `merged_by.login`, `merged_at`을 사용했다. 작성자가 OWNER/MEMBER이고 같은 사람이 실제 병합한 사례를 찾았다. 기존 설치/설정 변경은 하지 않았다.

## 조건 충족 후보

| 저장소 | 종류 | GitHub stars | 유지관리자 및 병합 시각 UTC | 가장 맞는 용도 |
|---|---|---:|---|---|
| [wshobson/agents](https://github.com/wshobson/agents) | Skills / plugin | 40,268 | OWNER `wshobson`, [PR #753](https://github.com/wshobson/agents/pull/753), 2026-10-04 20:42:52 | 사업계획, 시장성·수익성·자금 현실성 평가 |
| [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills) | Skills | 53,540 | OWNER `coreyhaines31`, [PR #654](https://github.com/coreyhaines31/marketingskills/pull/654), 2026-10-07 00:00:01 | 고객 수요 검증, 경쟁사 조사, 가격·GTM 구체화 |
| [sickn33/agentic-awesome-skills](https://github.com/sickn33/agentic-awesome-skills) | Skills collection | 47,316 | OWNER `sickn33`, [PR #1819](https://github.com/sickn33/agentic-awesome-skills/pull/1819), 2026-10-06 15:14:52 | 스타트업 분석·가격전략 등 여러 분야를 한 컬렉션에서 선택 |
| [exa-labs/exa-mcp-server](https://github.com/exa-labs/exa-mcp-server) | MCP + companion Skills | 5,089 | MEMBER `kesku`, [PR #453](https://github.com/exa-labs/exa-mcp-server/pull/453), 2026-10-06 03:48:29 | 시장·업계·경쟁사의 최신 근거 검색 |
| [firecrawl/firecrawl-mcp-server](https://github.com/firecrawl/firecrawl-mcp-server) | MCP | 7,566 | MEMBER `nickscamara`, [PR #499](https://github.com/firecrawl/firecrawl-mcp-server/pull/499), 2026-10-06 21:55:59 | 경쟁사 웹사이트·가격표·리뷰 등 자료 수집과 구조화 |

stars 원본은 각 저장소의 `https://api.github.com/repos/{owner}/{repo}` 응답 `stargazers_count`, 관리 활동 원본은 `https://api.github.com/repos/{owner}/{repo}/pulls/{number}` 응답이다. 아래 검증 스크립트로 재조회할 수 있다.

## 1. 가장 직접적인 선택: startup-business-analyst

`wshobson/agents`의 [startup-business-analyst](https://github.com/wshobson/agents/tree/main/plugins/startup-business-analyst)는 초기 사업 분석을 위한 5개 Skills, 3개 Commands, 1개 Agent로 구성된다. **시장 규모 → 경쟁 환경 → 매출·비용·현금흐름 → 실행계획**을 정리하려는 요청에 가장 가깝다. [공식 설명](https://github.com/wshobson/agents/blob/main/plugins/startup-business-analyst/README.md)

추천 스킬과 정확한 경로:

- [`market-sizing-analysis`](https://github.com/wshobson/agents/blob/main/plugins/startup-business-analyst/skills/market-sizing-analysis/SKILL.md): `plugins/startup-business-analyst/skills/market-sizing-analysis/SKILL.md`. TAM/SAM/SOM을 하향식·상향식·가치 기반 접근으로 계산한다.
- [`startup-financial-modeling`](https://github.com/wshobson/agents/blob/main/plugins/startup-business-analyst/skills/startup-financial-modeling/SKILL.md): `plugins/startup-business-analyst/skills/startup-financial-modeling/SKILL.md`. 3~5년 매출·비용·현금흐름, 운영 가능 기간, 보수적/기본/낙관적 시나리오를 만든다.
- [`competitive-landscape`](https://github.com/wshobson/agents/blob/main/plugins/startup-business-analyst/skills/competitive-landscape/SKILL.md): `plugins/startup-business-analyst/skills/competitive-landscape/SKILL.md`. 경쟁 포지셔닝, 차별화, 진입전략을 분석한다.
- [`startup-metrics-framework`](https://github.com/wshobson/agents/blob/main/plugins/startup-business-analyst/skills/startup-metrics-framework/SKILL.md): `plugins/startup-business-analyst/skills/startup-metrics-framework/SKILL.md`. 사업모델별 CAC/LTV·유지율 등 판단 지표를 선택한다.

초기 투자부터 Series A까지의 스타트업에 초점이 있고, 일부 보상·채용 벤치마크는 미국 중심이다. 한국 시장의 인건비·세금·규제·고객 규모는 별도의 현지 근거로 대체해야 한다. 이는 저장소의 설명을 바탕으로 한 적용상 판단이다. [플러그인 설명](https://github.com/wshobson/agents/blob/main/plugins/startup-business-analyst/README.md)

Claude Code의 Agent/Command가 Codex에서 그대로 제공된다고 보면 안 된다. 현재 저장소 README는 Codex native plugin이 원본 Skills를 노출하며 Agent/Command 변환에는 별도 adapter 경로가 필요하다고 구분한다. [지원 범위](https://github.com/wshobson/agents#codex-cli)

## 2. 수요·가격·판매전략 구체화: marketingskills

`coreyhaines31/marketingskills`는 기술 기반 마케터·창업자용 Skills이며 Claude Code, Codex, Cursor 등을 지원한다. 사업성이 확인되기 전에도 **누가 어떤 문제 때문에 돈을 내는가**를 검증하는 데 적합하다고 판단한다. [공식 README](https://github.com/coreyhaines31/marketingskills)

- [`customer-research`](https://github.com/coreyhaines31/marketingskills/blob/main/skills/customer-research/SKILL.md): `skills/customer-research/SKILL.md`. 인터뷰·설문·지원 티켓 분석, Reddit/G2/포럼 신호 탐색, 직접 고객 조사 설계를 다룬다.
- [`competitor-profiling`](https://github.com/coreyhaines31/marketingskills/blob/main/skills/competitor-profiling/SKILL.md): `skills/competitor-profiling/SKILL.md`. 경쟁사 URL을 받아 가격·포지셔닝 등을 비교 가능한 프로필로 정리한다. 관찰 사실/추론/시사점을 구분하고 출처를 요구한다. Firecrawl + DataForSEO를 선호하나 다른 자료원도 허용하며 SEO 수치가 없으면 추정하지 않는다.
- [`marketing-plan`](https://github.com/coreyhaines31/marketingskills/blob/main/skills/marketing-plan/SKILL.md): `skills/marketing-plan/SKILL.md`. 예산·팀·단계에 맞는 90일/12개월 GTM·성장계획을 만든다. 시장 규모 조사도 포함한다.
- [`pricing`](https://github.com/coreyhaines31/marketingskills/blob/main/skills/pricing/SKILL.md): `skills/pricing/SKILL.md`. 가격·패키징·수익모델 설계. 최신 v2에서는 예전 이름 `pricing-strategy`가 `pricing`으로 바뀌었다. [이름 변경표](https://github.com/coreyhaines31/marketingskills#full-rename-map)

핵심은 문구 작성보다 `customer-research`와 `competitor-profiling`을 먼저 쓰는 조합이다. 최신 시장자료 수집은 연결된 검색/수집 도구에 의존한다.

## 3. 큰 컬렉션을 선호할 때: agentic-awesome-skills

예전 `sickn33/antigravity-awesome-skills` 주소는 현재 `sickn33/agentic-awesome-skills`로 이동한다. [`startup-analyst`](https://github.com/sickn33/agentic-awesome-skills/blob/main/skills/startup-analyst/SKILL.md), [`market-sizing-analysis`](https://github.com/sickn33/agentic-awesome-skills/blob/main/skills/market-sizing-analysis/SKILL.md), [`startup-financial-modeling`](https://github.com/sickn33/agentic-awesome-skills/blob/main/skills/startup-financial-modeling/SKILL.md), [`pricing-strategy`](https://github.com/sickn33/agentic-awesome-skills/blob/main/skills/pricing-strategy/SKILL.md)를 선택할 수 있다. 경로는 각각 `skills/{이름}/SKILL.md`이다.

[`agentic-bundle-business-analyst`](https://github.com/sickn33/agentic-awesome-skills/tree/main/plugins/agentic-bundle-business-analyst)에는 business-analyst, market-sizing-analysis, startup-financial-modeling, startup-metrics-framework, kpi-dashboard-design이 묶여 있다. 처음 두 후보와 기능이 많이 겹치므로 함께 전부 설치할 필요는 없다고 판단한다.

[`apify-market-research`](https://github.com/sickn33/agentic-awesome-skills/blob/main/skills/apify-market-research/SKILL.md)는 Google Maps, 소셜, 숙박·여행 리뷰 등의 데이터 수집을 구체적으로 안내한다. 단순 무료 프롬프트만으로 실행되는 것이 아니라 APIFY_TOKEN, Node.js, mcpc CLI, 해당 Actor 실행이 필요하다.

## 4. 시장 근거 조사: Exa MCP

기본 도구는 `web_search_exa`와 `web_fetch_exa`이며, 선택적으로 `web_search_advanced_exa`·`agent_run`을 켤 수 있다. 시장 동향·경쟁사·고객 문제 근거를 찾아 분석 스킬에 전달하는 역할로 적합하다. 별도 [`skills/search`](https://github.com/exa-labs/exa-mcp-server/tree/main/skills/search), [`skills/exa-agent`](https://github.com/exa-labs/exa-mcp-server/tree/main/skills/exa-agent)도 제공한다. [공식 README](https://github.com/exa-labs/exa-mcp-server)

호스팅 MCP는 익명 사용에 rate limit이 있으며 높은 한도·Exa Agent 사용에는 OAuth 또는 API key가 필요하다. 이전 문서의 `company_research` 이름을 현재 제공 기능으로 추천하지 않는다. [현재 도구·인증 설명](https://github.com/exa-labs/exa-mcp-server#tools)

## 5. 경쟁사 자료를 표로 모으기: Firecrawl MCP

`firecrawl_search`로 검색, `firecrawl_scrape`로 알려진 URL의 Markdown/스키마 기반 JSON 추출, `firecrawl_map`으로 사이트 URL 탐색, `firecrawl_crawl`로 여러 페이지 수집이 가능하다. 사업 구상에서는 경쟁사 요금제·기능·고객군을 비교할 때 유용하다. [도구 선택 설명](https://github.com/firecrawl/firecrawl-mcp-server)

keyless 호스팅에서는 scrape/search/parse만 제한적으로 제공된다. crawl/map/agent 등은 API key가 필요하며, 실제 사용 한도·비용은 계정 조건에 따라 확인해야 한다. [공식 설치·인증 안내](https://github.com/firecrawl/firecrawl-mcp-server#hosted-mcp-keyless-free-tier)

## 조건에서 제외한 후보

- [alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills): 27,805 stars. market-research, CEO/CFO advisor 등이 관련되지만 조회 당시 main 최신 커밋은 2026-08-26이며 OWNER의 마지막 확인된 병합 [PR #997](https://github.com/alirezarezvani/claude-skills/pull/997)은 2026-08-30 09:46:14 UTC였다. 최근 2주 유지관리 근거를 확인하지 못했으므로 제외했다. 검색엔진의 최근 크롤링 날짜나 stars로 바뀌는 `updated_at`은 코드 관리 증거로 쓰지 않았다.
- Tavily MCP: 2,420 stars이나 조회된 main 최신 커밋이 2026-09-16으로, 이번 조사에서 최근 2주 관리 근거를 확보하지 못했다.
- Brave Search MCP: 조회 당시 1,485 stars로 최소 별점 조건 미충족.

## 추천 조합과 실제 사용 예

**최소 조합은 `wshobson/agents`의 사업 분석 Skills + Exa MCP**다. 사업 구상·타당성 분석 틀과 최신 근거 수집을 묶는 선택이다. 고객 인터뷰·가격·판매전략이 중심이면 `marketingskills`의 필요한 Skills를 추가하고, 경쟁사 사이트를 여러 개 구조화해 수집할 때 Firecrawl을 추가한다. 이는 기능 비교에 기반한 추천이며 실행 성능을 직접 벤치마크한 결과는 아니다.

예시 요청: “한국의 1인 학원 운영자를 위한 월 구독 SaaS를 검토해줘. 실제 고객 문제와 대안을 출처로 확인하고, 상향식 시장 규모, 경쟁 요금제, 초기 고객 10명 확보 방법, 보수적 매출·비용·현금흐름, 실패 조건과 2주 검증 실험을 정리해줘.”

분석 결과는 가설 검증을 준비하는 산출물이다. 고객 인터뷰·실제 구매·가격 실험 결과를 넣을수록 평가가 구체적이 된다. 어떤 스킬도 사업 성공을 입증해 주는 기능으로 설명하지 않는다.

## 재현 가능한 조건 검증

다음 명령은 조건 충족 후보의 stars 및 실제 유지관리자 병합을 GitHub 원본 API로 다시 확인한다. 네트워크/API 제한이 없으면 각 후보에 PASS를 출력한다. 재실행 시각 UTC를 종료로, 그 시각으로부터 정확히 14일 전을 시작으로 판정한다.

```bash
python3 - <<'PY'
import json, urllib.request
from datetime import datetime, timedelta, timezone
end = datetime.now(timezone.utc)
start = end - timedelta(days=14)
candidates = [
    ('wshobson/agents', 753),
    ('coreyhaines31/marketingskills', 654),
    ('sickn33/agentic-awesome-skills', 1819),
    ('exa-labs/exa-mcp-server', 453),
    ('firecrawl/firecrawl-mcp-server', 499),
]
def get(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'business-research'})
    return json.load(urllib.request.urlopen(request, timeout=20))
for repo, number in candidates:
    base = 'https://api.github.com/repos/' + repo
    metadata = get(base)
    pr = get(base + '/pulls/' + str(number))
    merged = datetime.fromisoformat(pr['merged_at'].replace('Z', '+00:00'))
    assert metadata['stargazers_count'] >= 2000, repo
    assert not metadata['archived'], repo
    assert pr['author_association'] in {'OWNER', 'MEMBER', 'COLLABORATOR'}, repo
    assert pr['merged_by']['login'] == pr['user']['login'], repo
    assert start <= merged < end, repo
    print(f"PASS {repo}: stars={metadata['stargazers_count']}, "
          f"{pr['author_association']}={pr['merged_by']['login']}, "
          f"merged_at={pr['merged_at']}")
print("5/5 meet repository-level stars and maintainer activity requirements")
PY
```

검증 출력 (2026-10-07, 메인 에이전트의 GitHub API 재조회):

```text
PASS wshobson/agents: stars=40268, OWNER=wshobson, merged_at=2026-10-04T20:42:52Z
PASS coreyhaines31/marketingskills: stars=53540, OWNER=coreyhaines31, merged_at=2026-10-07T00:00:01Z
PASS sickn33/agentic-awesome-skills: stars=47316, OWNER=sickn33, merged_at=2026-10-06T15:14:52Z
PASS exa-labs/exa-mcp-server: stars=5089, MEMBER=kesku, merged_at=2026-10-06T03:48:29Z
PASS firecrawl/firecrawl-mcp-server: stars=7566, MEMBER=nickscamara, merged_at=2026-10-06T21:55:59Z
5/5 meet repository-level stars and maintainer activity requirements
```

메인 에이전트의 전체 5개 검증은 성공했다. 이후 서브에이전트가 동일 API를 추가 재조회한 실행은 첫 후보 PASS 뒤 GitHub 익명 API의 `403: rate limit exceeded`로 중단됐다. 별점·병합 증거가 바뀌거나 assertion이 실패한 결과가 아니다.
