# NMC Basic Info discovery — latest verification 2026-09-14

The live development database was probed again at 01:36 KST. Discovery **7** passed in **NATIONWIDE (bulk)** mode, page size **100**, using **17 successful calls**. All 529 unique response HPIDs cover all 529 currently active Master records; missing and extra sets are empty. Repeated first-page order, six-page pagination, end page, and requested sizes 10/100/500/1000 passed. The maximum supported size remains unverified.

The earlier PER_HPID decision below was correct for its 530-record Master generation. The subsequent normal Master refresh made `A1500078` inactive; Basic sync did not change hospital activity. Collection mode must follow the latest passed discovery and actual Master coverage, rather than a permanent per-HPID setting.

A fresh `--sync-basic` completed at **2026-09-14 01:37:12 KST**: six successful requests, 529 snapshots, 529 published members, dataset `e32ce259-b8d8-432b-8612-eaa36402f5b6`. The previous dataset remains `4e4277c5-312c-41df-b468-5837fbd85a6b`. This verification consumed 23 Basic requests (17 discovery + 6 collection), taking the endpoint ledger from 553 to 576, within the existing 900-call rolling budget.

See [the final user acceptance report](../operations/basic-info-acceptance-2026-09-14.md) for DB/API comparisons and Android evidence.

## Historical discovery — 2026-09-13


Authenticated requests use the shared PostgreSQL endpoint guard. No Master or published Basic dataset is written by discovery.

Unfiltered pagination returned 529 unique institutions, but did not cover all 530 active Master institutions. The missing HPID was also queried explicitly and returned a successful empty response. The approved collection mode is therefore PER_HPID, with explicit absence recorded independently from hospital existence. HPIDs below are empirical evidence, never production selection constants.

The initial 17 calls were supplemented by five geographically distributed samples and one missing-HPID check (23 calls total). All succeeded without retries. Requests of 10/100/500/1000 were observed to work; no maximum is asserted.

The department allowlist contains literal department tokens observed in the authenticated nationwide response; it does not map specialties or infer current availability. No explicit not-provided token was observed. Missing tags remain MISSING. 0000 and 2400 remain UNVERIFIED. dutyTel3 was absent in all 529 records and is not filled from another endpoint.

```json
{
  "id": 6,
  "mode": "PER_HPID",
  "status": "PASSED",
  "extraHpids": [],
  "totalCount": 529,
  "bulkFailure": "BASIC_MASTER_COVERAGE_MISSING",
  "completedAt": "2026-09-13T11:15:58.786642Z",
  "probeVersion": "basic-probe-v1",
  "safePageSize": 10,
  "maximumPageSize": "UNVERIFIED",
  "uniqueHpidCount": 529,
  "activeMasterCount": 530,
  "missingMasterHpids": [
    "A1500078"
  ],
  "confirmedAbsentHpids": [
    "A1500078"
  ],
  "endpoint": "getEgytBassInfoInqire",
  "pdfSha256": "bd2df91278c3f3e4553d62c44267e60bb290f57418a8563e87a84da0499d2f60",
  "cumulativeSuccessfulCalls": 23,
  "bulkObservedPageSize": 100,
  "calls": [
    {
      "unit": "HPID:A1100006",
      "pageNo": 1,
      "fetchedAt": "2026-09-13T11:13:32.132523Z",
      "numOfRows": 10,
      "responseId": 81,
      "totalCount": 1,
      "actualCount": 1,
      "requestedPage": 1,
      "requestedSize": 10
    },
    {
      "unit": "HPID:A1100052",
      "pageNo": 1,
      "fetchedAt": "2026-09-13T11:13:33.267337Z",
      "numOfRows": 10,
      "responseId": 82,
      "totalCount": 1,
      "actualCount": 1,
      "requestedPage": 1,
      "requestedSize": 10
    },
    {
      "unit": "HPID:A1100004",
      "pageNo": 1,
      "fetchedAt": "2026-09-13T11:13:34.380648Z",
      "numOfRows": 10,
      "responseId": 83,
      "totalCount": 1,
      "actualCount": 1,
      "requestedPage": 1,
      "requestedSize": 10
    },
    {
      "unit": "HPID:A1100013",
      "pageNo": 1,
      "fetchedAt": "2026-09-13T11:13:34.994816Z",
      "numOfRows": 10,
      "responseId": 84,
      "totalCount": 1,
      "actualCount": 1,
      "requestedPage": 1,
      "requestedSize": 10
    },
    {
      "unit": "HPID:A1100002",
      "pageNo": 1,
      "fetchedAt": "2026-09-13T11:13:35.616957Z",
      "numOfRows": 10,
      "responseId": 85,
      "totalCount": 1,
      "actualCount": 1,
      "requestedPage": 1,
      "requestedSize": 10
    },
    {
      "unit": "SIZE:10",
      "pageNo": 1,
      "fetchedAt": "2026-09-13T11:13:36.482385Z",
      "numOfRows": 10,
      "responseId": 86,
      "totalCount": 529,
      "actualCount": 10,
      "requestedPage": 1,
      "requestedSize": 10
    },
    {
      "unit": "SIZE:100",
      "pageNo": 1,
      "fetchedAt": "2026-09-13T11:13:37.404271Z",
      "numOfRows": 100,
      "responseId": 87,
      "totalCount": 529,
      "actualCount": 100,
      "requestedPage": 1,
      "requestedSize": 100
    },
    {
      "unit": "SIZE:500",
      "pageNo": 1,
      "fetchedAt": "2026-09-13T11:13:38.506167Z",
      "numOfRows": 500,
      "responseId": 88,
      "totalCount": 529,
      "actualCount": 500,
      "requestedPage": 1,
      "requestedSize": 500
    },
    {
      "unit": "SIZE:1000",
      "pageNo": 1,
      "fetchedAt": "2026-09-13T11:13:40.130099Z",
      "numOfRows": 1000,
      "responseId": 89,
      "totalCount": 529,
      "actualCount": 529,
      "requestedPage": 1,
      "requestedSize": 1000
    },
    {
      "unit": "BULK:1",
      "pageNo": 1,
      "fetchedAt": "2026-09-13T11:13:41.554411Z",
      "numOfRows": 100,
      "responseId": 90,
      "totalCount": 529,
      "actualCount": 100,
      "requestedPage": 1,
      "requestedSize": 100
    },
    {
      "unit": "BULK:2",
      "pageNo": 2,
      "fetchedAt": "2026-09-13T11:13:42.473195Z",
      "numOfRows": 100,
      "responseId": 91,
      "totalCount": 529,
      "actualCount": 100,
      "requestedPage": 2,
      "requestedSize": 100
    },
    {
      "unit": "BULK:3",
      "pageNo": 3,
      "fetchedAt": "2026-09-13T11:13:43.358438Z",
      "numOfRows": 100,
      "responseId": 92,
      "totalCount": 529,
      "actualCount": 100,
      "requestedPage": 3,
      "requestedSize": 100
    },
    {
      "unit": "BULK:4",
      "pageNo": 4,
      "fetchedAt": "2026-09-13T11:13:44.264039Z",
      "numOfRows": 100,
      "responseId": 93,
      "totalCount": 529,
      "actualCount": 100,
      "requestedPage": 4,
      "requestedSize": 100
    },
    {
      "unit": "BULK:5",
      "pageNo": 5,
      "fetchedAt": "2026-09-13T11:13:45.711830Z",
      "numOfRows": 100,
      "responseId": 94,
      "totalCount": 529,
      "actualCount": 100,
      "requestedPage": 5,
      "requestedSize": 100
    },
    {
      "unit": "BULK:6",
      "pageNo": 6,
      "fetchedAt": "2026-09-13T11:13:47.084916Z",
      "numOfRows": 100,
      "responseId": 95,
      "totalCount": 529,
      "actualCount": 29,
      "requestedPage": 6,
      "requestedSize": 100
    },
    {
      "unit": "END",
      "pageNo": 7,
      "fetchedAt": "2026-09-13T11:13:48.461075Z",
      "numOfRows": 100,
      "responseId": 96,
      "totalCount": 529,
      "actualCount": 0,
      "requestedPage": 7,
      "requestedSize": 100
    },
    {
      "unit": "REPEAT",
      "pageNo": 1,
      "fetchedAt": "2026-09-13T11:13:49.397812Z",
      "numOfRows": 100,
      "responseId": 97,
      "totalCount": 529,
      "actualCount": 100,
      "requestedPage": 1,
      "requestedSize": 100
    },
    {
      "unit": "HPID:A2200001",
      "pageNo": 1,
      "fetchedAt": "2026-09-13T11:15:53.436338Z",
      "numOfRows": 10,
      "responseId": 98,
      "totalCount": 1,
      "actualCount": 1,
      "requestedPage": 1,
      "requestedSize": 10
    },
    {
      "unit": "HPID:A2100001",
      "pageNo": 1,
      "fetchedAt": "2026-09-13T11:15:54.081518Z",
      "numOfRows": 10,
      "responseId": 99,
      "totalCount": 1,
      "actualCount": 1,
      "requestedPage": 1,
      "requestedSize": 10
    },
    {
      "unit": "HPID:A2800001",
      "pageNo": 1,
      "fetchedAt": "2026-09-13T11:15:54.724784Z",
      "numOfRows": 10,
      "responseId": 100,
      "totalCount": 1,
      "actualCount": 1,
      "requestedPage": 1,
      "requestedSize": 10
    },
    {
      "unit": "HPID:A2700007",
      "pageNo": 1,
      "fetchedAt": "2026-09-13T11:15:55.843190Z",
      "numOfRows": 10,
      "responseId": 101,
      "totalCount": 1,
      "actualCount": 1,
      "requestedPage": 1,
      "requestedSize": 10
    },
    {
      "unit": "HPID:A1300001",
      "pageNo": 1,
      "fetchedAt": "2026-09-13T11:15:56.978406Z",
      "numOfRows": 10,
      "responseId": 102,
      "totalCount": 1,
      "actualCount": 1,
      "requestedPage": 1,
      "requestedSize": 10
    },
    {
      "unit": "MISSING:A1500078",
      "pageNo": 1,
      "fetchedAt": "2026-09-13T11:15:58.201336Z",
      "numOfRows": 10,
      "responseId": 103,
      "totalCount": 0,
      "actualCount": 0,
      "requestedPage": 1,
      "requestedSize": 10
    }
  ],
  "fieldDiscovery": {
    "responseTypes": "XML text; no coercion",
    "fieldPresenceCounts": {
      "dgidIdName": 513,
      "dutyAddr": 529,
      "dutyEryn": 529,
      "dutyHano": 529,
      "dutyHayn": 529,
      "dutyName": 529,
      "dutyTel1": 529,
      "dutyTime1c": 528,
      "dutyTime1s": 528,
      "dutyTime2c": 528,
      "dutyTime2s": 528,
      "dutyTime3c": 528,
      "dutyTime3s": 528,
      "dutyTime4c": 529,
      "dutyTime4s": 529,
      "dutyTime5c": 529,
      "dutyTime5s": 529,
      "dutyTime6c": 421,
      "dutyTime6s": 421,
      "hpbdn": 440,
      "hperyn": 441,
      "hpgryn": 429,
      "hpicuyn": 252,
      "hpid": 529,
      "hpnicuyn": 107,
      "hpopyn": 424,
      "hvec": 455,
      "hvgc": 453,
      "hvicc": 268,
      "hvncc": 107,
      "hvoc": 438,
      "MKioskTy1": 207,
      "MKioskTy11": 281,
      "MKioskTy2": 177,
      "MKioskTy25": 81,
      "MKioskTy3": 176,
      "MKioskTy4": 231,
      "MKioskTy6": 92,
      "MKioskTy7": 274,
      "MKioskTy8": 204,
      "MKioskTy9": 276,
      "postCdn1": 529,
      "postCdn2": 529,
      "wgs84Lat": 529,
      "wgs84Lon": 529,
      "dutyMapimg": 260,
      "MKioskTy10": 101,
      "MKioskTy5": 77,
      "dutyInf": 231,
      "hvccc": 34,
      "hpccuyn": 34,
      "hpcuyn": 32,
      "hvcc": 33,
      "dutyTime7c": 38,
      "dutyTime7s": 38,
      "dutyTime8c": 44,
      "dutyTime8s": 44
    },
    "unmappedFields": [
      "MKioskTy1",
      "MKioskTy10",
      "MKioskTy11",
      "MKioskTy2",
      "MKioskTy25",
      "MKioskTy3",
      "MKioskTy4",
      "MKioskTy5",
      "MKioskTy6",
      "MKioskTy7",
      "MKioskTy8",
      "MKioskTy9",
      "dutyEryn",
      "dutyHano",
      "dutyHayn",
      "dutyInf",
      "dutyMapimg",
      "hpbdn",
      "hpccuyn",
      "hpcuyn",
      "hperyn",
      "hpgryn",
      "hpicuyn",
      "hpnicuyn",
      "hpopyn",
      "hvcc",
      "hvccc",
      "hvec",
      "hvgc",
      "hvicc",
      "hvncc",
      "hvoc",
      "postCdn1",
      "postCdn2",
      "wgs84Lat",
      "wgs84Lon"
    ],
    "emptyFields": 0,
    "repeatedItemFields": 0,
    "departmentRecords": 513,
    "maxDepartmentTextLength": 251,
    "observedDelimiter": ",",
    "specialTimes": [
      "0000",
      "2400"
    ]
  }
}
```
