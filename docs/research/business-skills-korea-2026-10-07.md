# 기존 사업 스킬·MCP 후보의 한국 시장 적합성

확인일: 2026-10-07. 기존 5개 후보의 공식 저장소·공식 API 문서와 국내 공공기관 문서를 확인했다. 스타·유지관리 조건은 이전 조사 결과를 전제로 한다. 설치, 유료 API 호출, 실제 한국어 검색·수집 성능 시험은 하지 않았다. 아래 적합성은 문서와 소스에 근거한 판단이며 실측 점수가 아니다.

## 결론

**한국 시장에서도 분석 틀로는 유용하다. 다만 한국어로 답하게 하는 것과 한국 시장의 근거를 확보하는 것은 별개다.** 시장 규모, 손익, 고객 인터뷰, 경쟁 비교는 재사용할 수 있지만 기본 사례·벤치마크·조사 채널을 한국의 실제 자료로 교체해야 한다.

추천 구성은 `startup-business-analyst` + **Exa 고급 검색의 한국 지역 설정** + **KOSIS·공공데이터포털·DART·네이버의 국내 자료**다. 고객 조사·판매 전략에는 `marketingskills`를 보충하고, Firecrawl은 알려진 공개 경쟁사 페이지의 가격·기능 수집에 필요할 때 사용한다. 이는 아래 문서 비교에 따른 추천이다.

## 후보별 판단

| 후보 | 한국 사업에서 쓸 부분 | 필요한 보정 | 판단 |
|---|---|---|---|
| wshobson/agents의 startup-business-analyst | 시장 규모, 경쟁 구조, 손익·현금흐름 시나리오 | 국내 고객 수·가격·인건비·사업 모델로 계산 | 분석 틀 우선 추천 |
| coreyhaines31/marketingskills | 고객 문제, 인터뷰, 지불 의향, 가격·판매 전략 | 국내 고객 원문과 실제 이용 채널로 조사 | 고객 검증 보충 추천 |
| sickn33/agentic-awesome-skills | 필요한 사업 스킬을 골라 활용 | 동일한 미국 중심 기본값 보정 | 중복이 많아 별도 우선 설치 근거 약함 |
| Exa MCP | 한국 관련 공개 웹·공식 자료 발견 | 고급 검색에 KR 및 국내 도메인 지정 | 검색 보조 추천, 한국 성능 미검증 |
| Firecrawl MCP | 알려진 공개 페이지의 본문·가격·기능 추출 | 한국 위치 설정, 접근 가능한 실제 URL 확인 | 경쟁사 자료 수집에 조건부 추천 |

이 표의 판단은 아래 검토한 기능과 한계에서 도출한 추론이다.

## 실제 확인한 기본값과 편향

### startup-business-analyst

공식 에이전트는 pre-seed~Series A 기업을 중심으로 시장 규모·재무·경쟁·채용·투자유치 분석을 수행하며 출처와 날짜를 요구한다. **한국 전용 전문가나 국내 데이터 커넥터가 들어 있다는 의미는 아니다.** [공식 에이전트](https://github.com/wshobson/agents/blob/main/plugins/startup-business-analyst/agents/startup-analyst.md)

채용 스킬은 미국 2024년 기본급, 미국 급여세 FICA, 401k, 미국 도시별 지역 조정을 명시한다. 따라서 해당 숫자를 환율로 바꿔 한국 인건비로 쓰면 근거가 맞지 않는다. 국내 연봉·사업주 부담·퇴직급여 등 필요한 항목을 별도 자료로 산정해야 한다는 판단이다. [채용 스킬 원문](https://github.com/wshobson/agents/blob/main/plugins/startup-business-analyst/skills/team-composition-analysis/SKILL.md)

### marketingskills

`customer-research`는 기존 고객 자료, 온라인 커뮤니티, 인터뷰·설문을 구분하고 페르소나를 지어내지 말라고 지시한다. 반면 권장 조사 채널은 Reddit, G2/Capterra, Hacker News, LinkedIn, Indie Hackers, SparkToro 등이 중심이다. 한국 고객 대상으로는 실제 고객 인터뷰와 국내 리뷰·커뮤니티를 지정해야 한다는 판단이다. 네이버·카카오의 데이터를 기본으로 연결한다는 내용은 검토한 스킬 본문에서 확인되지 않았다. [고객 조사 스킬](https://github.com/coreyhaines31/marketingskills/blob/main/skills/customer-research/SKILL.md)

`marketing-plan`은 기존 고객·제품 문맥을 바탕으로 목표와 실행계획을 설계하는 문서다. 네이버 검색·쇼핑, 카카오, 당근 등 국내 채널은 사업 대상 고객이 실제 사용하는지를 확인한 뒤 넣어야 한다. 국내 채널이 모든 사업에 맞는다는 뜻은 아니다. [마케팅 계획 스킬](https://github.com/coreyhaines31/marketingskills/blob/main/skills/marketing-plan/SKILL.md)

### agentic-awesome-skills

이 컬렉션의 `startup-analyst`도 미국 중심 2024년 보상 벤치마크를 명시한다. 컬렉션 규모나 인기가 한국 현지화의 증거는 아니라는 판단이다. [스킬 원문](https://github.com/sickn33/agentic-awesome-skills/blob/master/skills/startup-analyst/SKILL.md)

## MCP의 한국 지역 지원: API와 도구를 구별

### Exa

공식 API의 `userLocation`은 두 글자 국가 코드로 결과를 현지화하고 `includeDomains`로 도메인을 제한할 수 있다. [Search API](https://exa.ai/docs/reference/search)

실제 MCP 소스도 **고급 도구** `web_search_advanced_exa`에 `userLocation`과 `includeDomains`를 노출하고 API로 전달한다. 한국을 대상으로 `userLocation: "KR"`와 국내 공식 도메인 제한을 사용할 수 있다는 것은 소스로 확인한 기능이다. 기본 `web_search_exa`는 `query`, `numResults`만 노출하므로 고급 도구를 별도로 활성화해야 한다. [고급 도구 소스](https://github.com/exa-labs/exa-mcp-server/blob/main/src/tools/webSearchAdvanced.ts), [기본 도구 소스](https://github.com/exa-labs/exa-mcp-server/blob/main/src/tools/webSearch.ts), [도구 활성화 안내](https://github.com/exa-labs/exa-mcp-server#available-tools)

이 설정은 **네이버 검색 인덱스 전체 접근이나 한국어 검색 품질 보장**을 뜻하지 않는다. 한국 사업에 쓰려면 실제 질문 몇 개로 국내 자료 누락과 출처 품질을 확인해야 한다.

### Firecrawl

공식 Search API는 `location`과 `country`를 지원하며 `country` 기본값은 US다. [Search API](https://docs.firecrawl.dev/api-reference/endpoint/search#country-parameter)

그러나 현재 MCP 소스의 공통 검색 필드는 **`location`만 노출하고 최상위 `country`는 노출하지 않는다.** 따라서 API의 `country: "KR"`를 MCP에서도 그대로 사용할 수 있다고 안내하면 부정확하다. 스크레이프에는 `location: {country, languages}`가 별도로 존재한다. 검색 위치와 페이지 수집 위치는 서로 다른 설정이다. [실제 MCP 스키마](https://github.com/firecrawl/firecrawl-mcp-server/blob/main/src/index.ts)

공식 문서의 위치 설정은 특정 국가를 겨냥하는 기능이다. 한국 사이트·네이버 카페·쿠팡 등의 실제 접근·수집 성공률은 이번 조사에서 검증하지 않았다. 공개 URL을 수집할 수 있다는 기능만으로 로그인 게시물·플랫폼 내부 자료·실제 매출까지 확보한다고 간주할 수 없다. [위치 설정 안내](https://docs.firecrawl.dev/features/search#location-customization)

## 국내 근거를 보충할 출처

| 조사 목적 | 공식 출처 | 활용 및 범위 |
|---|---|---|
| 국내·지역별 시장 모수 | [KOSIS OpenAPI](https://kosis.kr/openapi/devGuide/devGuide_0101List.do) | 국내통계·지방지표, 통계자료와 설명 확인. API에는 인증키 필요 |
| 지역·분야별 공공 데이터 | [공공데이터포털](https://www.data.go.kr/) | 파일·OpenAPI와 지역별 포털 제공. 사업에 맞는 데이터셋의 항목·갱신일을 확인 |
| 공시 기업의 경쟁·재무 근거 | [OpenDART](https://opendart.fss.or.kr/intro/infoApiList.do) | 공시·재무제표·회사 간 계정 비교. 공시 자료를 시장 전체의 고객 수로 확대 해석하지 않음 |
| 국내 검색·관심 추세 | [네이버 공식 이관 공지](https://developers.naver.com/notice/article/32530) | 최신 제공 경로·종료 기능을 확인한 뒤 사용. 검색 관심을 실제 구매·매출로 취급하지 않음 |

이 출처는 국내 근거의 보완책이며 앞서 요구한 2,000 스타 조건을 만족하는 별도 MCP 후보로 제시한 것이 아니다. 공식 웹·파일·API를 사용하면 되고, 반드시 비공식 MCP를 추가 설치할 필요는 없다는 판단이다.

네이버 공식 공지에 따르면 2026-06-25 Search/Search Trend/Shopping Insight가 API HUB로 이관됐다. 2026-07-31 기존 개발자센터 신규 신청이 중단되고 쇼핑·책·전문자료 검색 API는 대체 API 없이 종료됐다. 따라서 **이전 Shopping Search API를 한국 사업 조사 구성으로 권장하지 않는다.** 해당 3개 API의 기존 개발자센터 지원 종료 예정일은 2027-06-30이다. [공지](https://developers.naver.com/notice/article/32530)

## 사업 유형에 따른 적용 판단

- 한국 B2B SaaS: 분석 틀의 적합성이 비교적 높다는 판단. 국내 고객 수·계약 가격·도입 절차를 확보하고 해외 SaaS 지표는 비교 자료로만 사용한다.
- 국내 소비재·커머스: 공개 웹 검색만으로 수요를 확정하기 어렵다는 판단. 국내 플랫폼 리뷰·현재 가격·고객 인터뷰와 작은 판매 실험을 보충한다.
- 동네 서비스·오프라인 사업: 투자유치 중심 분석만으로는 부족하다는 판단. 지역 고객 수·임대료·가동률·반복구매로 손익을 계산한다.

예시 지시: “대한민국의 [고객군]을 대상으로 검토해줘. KOSIS·공공데이터포털·DART와 국내 경쟁사의 현재 가격을 우선 근거로 쓰고, 미국 연봉·채널·SaaS 벤치마크는 한국 수치로 치환하지 마. 확인된 사실·가정·미확인 항목을 구분하고 보수적 손익과 2주 고객 검증 실험을 제안해줘.”

## 검증 범위

원문과 실제 MCP 스키마를 대조한 문서 조사다. 한국어 출력 품질, 네이버·카카오·쿠팡 등의 수집 성공률, 사업 판단 정확도를 실측하지 않았다. 문서 링크·주요 판단 구분에 대한 로컬 확인만 수행하며 서비스 실행 검증을 대신하지 않는다.
