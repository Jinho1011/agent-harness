# 한국 사업 구상용 KOSIS·OpenDART MCP의 v1 범위 근거

확인일 2026-10-08. 공식 문서만 확인한 계획 단계 조사다. API 키 발급·실데이터 호출·설치·배포는 하지 않았다. 확인된 API 기능과 구현 제안을 구분한다.

## KOSIS: 통계표 발견과 조회

**통합검색 API가 실제로 존재한다.** 정적 통계표 목록만으로 검색을 구현할 필요는 없다. 다만 검색 결과가 사용자의 산업·지역에 맞는 지표라는 의미는 아니다.

| 공식 API | 확인된 입력·출력 | 가능한 도구 |
|---|---|---|
| `GET /openapi/statisticsSearch.do?method=getList` | 필수 `apiKey`, `searchNm`, `format`; 선택 기관 `orgId`, 정렬 `sort=RANK/DATE`, 페이지 `startCount`, 개수 `resultCount`. 응답 기관·통계표 ID/명, 조사명, 주요내용, 수록 시작·종료기간, 주석, 표 URL | 키워드 후보 검색 |
| `GET /openapi/statisticsList.do?method=getList` | 주제·기관·지역 등 서비스뷰 `vwCd`와 시작목록에 따른 계층 탐색. 응답 목록 ID·명 또는 기관·통계표 ID·명, 최종갱신일 | 분류별 목록 탐색 |
| `GET /openapi/statisticsData.do?method=getMeta&type=TBL` 및 설명 하위 기능 | 기관·표 ID를 통해 표명 확인. 설명 페이지는 수록정보, 분류/항목, 주석, 단위, 출처, 자료갱신일 등 별도 기능 제공 | 표 구조·근거 확인 |
| `GET /openapi/Param/statisticsParameterData.do?method=getList` | `orgId`, `tblId`, `objL1`, `itmId`, `prdSe` 필수; 분류2~8 선택. 기간 또는 최근 시점 개수 지정 | 선택한 차원의 수치 조회 |

공식 문서: [통합검색](https://kosis.kr/openapi/devGuide/devGuide_0701List.do), [목록](https://kosis.kr/openapi/devGuide/devGuide_0101List.do), [통계표설명](https://kosis.kr/openapi/devGuide/devGuide_060101List.do), [자료 조회](https://kosis.kr/openapi/devGuide/devGuide_0201List.do).

자료 조회 응답에는 분류 코드·이름 C1~C8, 항목, 단위, 주기 `PRD_SE`, 수록시점 `PRD_DE`, 수치 문자열 `DT`, 최종수정일 `LST_CHN_DE`가 있다. 최신 조회는 `newEstPrdCnt` 또는 기간 생략 시 최근 한 시점을 쓴다. 수록시점과 수정일은 다른 의미로 보존해야 한다. 통계부호 출력 `smblChk`가 있으므로 결측·비공개 등의 부호를 0으로 바꾸면 안 된다는 구현 판단이다. [자료 조회](https://kosis.kr/openapi/devGuide/devGuide_0201List.do)

메타데이터의 개별 하위 기능에 쓰는 정확한 `type` 값과 출력 스키마는 이번 짧은 조사에서 모두 확보하지 않았다. 구현 시 해당 설명 페이지의 하위 기능 또는 공식 개발가이드로 확인해야 한다. 특히 목록 문서는 입력 표의 `parentId`와 예제의 `parentListId`가 달라 실호출 확인이 필요하다. [설명](https://kosis.kr/openapi/devGuide/devGuide_060101List.do), [목록](https://kosis.kr/openapi/devGuide/devGuide_0101List.do)

**v1 제안:** 키워드로 후보를 찾고 → 메타데이터로 지역·산업·단위·기간을 확인하고 → 조회하는 흐름. 소수의 검증된 대표 통계표 레지스트리는 지표 추천 정확도를 높이는 보완책이다. 임의 사업 설명을 받아 모든 통계표의 업종·지역 코드를 자동 확정하는 기능은 검증 전 약속하지 않는다. KOSIS 표의 사업체 수·인구를 실제 유료 고객 수나 매출로 단정하지 않는다.

## OpenDART: 회사 식별·공시·재무

| 기능 | 공식 API·확인 사항 |
|---|---|
| 회사명→고유번호 후보 | `GET /api/corpCode.xml`: 실제 출력은 ZIP 내부 XML. `corp_code` 8자리, 정식명, 영문명, 상장사 종목코드 6자리, 정보변경일. 기업명 동명 후보는 사용자가 식별할 수 있도록 반환 |
| 공시 검색 | `GET /api/list.json`: 회사·접수기간·공시유형·페이지 조건; 회사코드 생략 시 최대 3개월 범위. `last_reprt_at=Y`는 최종보고서만, 기본 N은 정정을 포함한 전체. 반환 접수번호·보고서명·접수일·정정 관련 비고 |
| 재무 조회 | `GET /api/fnlttSinglAcntAll.json`: 회사코드, 사업연도(2015년 이후), 보고서 코드, `fs_div` 필수. 분기 11013/11014, 반기 11012, 사업보고서 11011; OFS와 CFS 구분 |

공식 문서: [고유번호](https://opendart.fss.or.kr/guide/detail.do?apiGrpCd=DS001&apiId=2019018), [공시검색](https://opendart.fss.or.kr/guide/detail.do?apiGrpCd=DS001&apiId=2019001), [전체 재무제표](https://opendart.fss.or.kr/guide/detail.do?apiGrpCd=DS003&apiId=2019020).

재무 응답은 접수번호, 표 구분(BS/IS/CIS/CF/SCE), 계정ID·명, 당기·누적·전기 금액, 통화 `currency`를 제공한다. 손익계산서 분·반기 `thstrm_amount`는 3개월 금액으로 설명돼 있어 누적금액과 구분해야 한다. 비표준 계정ID도 가능하므로 계정명만으로 매출·이익을 무조건 매핑하지 않는 구현이 필요하다는 판단이다. 통화는 API 필드로 보존하고, 화면의 ‘백만원’ 단위를 JSON 숫자에 임의 적용하지 않는다. [재무 개발가이드](https://opendart.fss.or.kr/guide/detail.do?apiGrpCd=DS003&apiId=2019020)

재무 API 대상은 유가증권·코스닥 및 사업보고서 제출대상이면서 IFRS 적용인 주요 비상장법인이다. 모든 국내 기업·소상공인·초기 스타트업을 포괄하지 않는다. 회사가 고유번호 목록에 있다고 전체 재무제표 API 대상임이 보장되지는 않는다는 판단이다. 제공 수치는 정정으로 바뀔 수 있으며 금감원은 완전성·정확성을 보장하지 않는다고 명시한다. [대상과 정정 안내](https://opendart.fss.or.kr/guide/main.do?apiGrpCd=DS003)

**v1 제안:** 회사 후보 찾기, 최종 공시 링크 확인, 명시적 CFS/OFS·기간에 따른 재무 원자료 반환. 접수번호·조회시각·사업연도·보고서·표종류·통화 보존. CFS가 없다고 조용히 OFS로 바꾸거나, 조회없음을 매출 0으로 표시하지 않는다. 본문 사업부문 매출을 완전 자동 추출하는 기능과 기업 전체의 실시간 경쟁사 탐색은 별도 범위다.

## 키·쿼터·공개 배포·재배포 조건

KOSIS 공식 소개는 조회 서비스별 분당 200회 제한과 보통 1회 40,000셀 제한을 안내한다. 대용량 XLS는 200,000셀을 별도로 명시한다. 통계표 구조·기간을 좁히는 조회와 호출 제한이 필요한 근거다. [서비스 소개](https://kosis.kr/openapi/introduce/introduce_01List.do)

OpenDART 가이드는 020 요청 제한 초과가 일반적으로 20,000건 이상에서 발생하지만 설정에 따라 다르다고 설명한다. 해당 문구만으로 모든 이용자에 대해 ‘하루 20,000건 보장’이라고 적지 않는다. 정확한 계정별 허용량은 발급 시 확인할 항목이다. [메시지 안내](https://opendart.fss.or.kr/guide/detail.do?apiGrpCd=DS003&apiId=2019020)

KOSIS는 출처표시 의무, 상업 활용 가능(예외 존재), 원자료를 특정 서비스 플랫폼 없이 그대로 제3자에게 유료 제공·공유하는 행위 금지, 인증키 무단 양도 금지 등을 규정한다. 국제통계의 라이선스 제약도 명시한다. 따라서 소스 코드 공개와 공공 원자료의 무조건적 재판매·번들 재배포는 별개다. [KOSIS 약관](https://kosis.kr/openapi/introduce/introduce_02List.do)

OpenDART는 원칙적 무료와 사용량 제한, 인증키 제3자 이용 금지를 규정하며 미명시 저작권 사항은 관련 법에 따른다고 한다. 이 약관만으로 모든 공시 원문의 무조건적 재배포 라이선스를 확인했다고 주장할 수 없다. [OpenDART 약관](https://opendart.fss.or.kr/intro/terms.do)

**배포 제안:** 공개 저장소는 코드·스킬·출처 링크·키 없는 설정 예시를 배포하고 사용자는 자기 키를 로컬 환경변수로 넣는 stdio MCP를 기본으로 삼는다. 서버가 GET API로 조회하는 기능은 읽기 전용으로 설계할 수 있다. 공용 운영자의 키로 불특정 다수에게 서비스하는 호스팅은 키 공유·사용환경 약관 해석과 운영 쿼터를 추가 확인할 대상이다. 이번 조사에서 hosted 서비스가 금지 또는 허용이라고 확정하지 않았다.

**캐시 제안:** 같은 요청 중복 억제와 조회시각·출처·기간 보존에 사용하는 로컬 캐시는 실무 제안이다. 공식 약관에서 일괄적으로 허용되는 저장 기간이나 원자료 재배포 권리를 확인하지 못했다. 정정 데이터가 있으므로 캐시된 값은 최신성과 조회시각을 표시하고 새 조회로 갱신 가능해야 한다.

## v1에 가능한 모듈과 남은 검증

가능한 최소 모듈은 KOSIS 검색·메타데이터·선택 조회, DART 회사번호 검색·공시목록·재무조회, 그리고 출처·가정·자료 공백을 구분해 사업 아이디어·시장 모수·손익·고객 검증 실험을 만드는 스킬이다. 사업 성공확률, 전국 모든 기업 재무, 국내 플랫폼 수요·매출 자동 수집은 이 두 API로 제공할 수 있는 범위가 아니다.

실제 구현 전 확인할 항목: KOSIS 메타데이터 하위 type/응답·목록 파라미터 차이, 승인된 키의 실호출·쿼터, 표별 지역·산업 코드와 결측 부호, DART 분기·누적·정정·비표준계정 응답, 배포할 개별 데이터의 이용 조건. 이번 결과는 구현 계획 근거이며 실행 성능을 검증한 결과가 아니다.
