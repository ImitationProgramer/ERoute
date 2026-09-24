# NMC nationwide discovery

Real authenticated requests, all counted in the PostgreSQL endpoint budget ledger.

```json
{
  "status": "PASSED",
  "calls": [
    {
      "scope": "NATIONWIDE",
      "requestedPage": 1,
      "requestedSize": 10,
      "pageNo": 1,
      "numOfRows": 10,
      "totalCount": 531,
      "actualCount": 10,
      "fetchedAt": "2026-09-09T01:00:39.790099+00:00"
    },
    {
      "scope": "NATIONWIDE",
      "requestedPage": 1,
      "requestedSize": 100,
      "pageNo": 1,
      "numOfRows": 100,
      "totalCount": 531,
      "actualCount": 100,
      "fetchedAt": "2026-09-09T01:00:40.512917+00:00"
    },
    {
      "scope": "NATIONWIDE",
      "requestedPage": 1,
      "requestedSize": 500,
      "pageNo": 1,
      "numOfRows": 500,
      "totalCount": 531,
      "actualCount": 500,
      "fetchedAt": "2026-09-09T01:00:41.269468+00:00"
    },
    {
      "scope": "NATIONWIDE",
      "requestedPage": 1,
      "requestedSize": 1000,
      "pageNo": 1,
      "numOfRows": 1000,
      "totalCount": 531,
      "actualCount": 531,
      "fetchedAt": "2026-09-09T01:00:42.107358+00:00"
    },
    {
      "scope": "NATIONWIDE",
      "requestedPage": 1,
      "requestedSize": 100,
      "pageNo": 1,
      "numOfRows": 100,
      "totalCount": 531,
      "actualCount": 100,
      "fetchedAt": "2026-09-09T01:00:42.922043+00:00"
    },
    {
      "scope": "NATIONWIDE",
      "requestedPage": 2,
      "requestedSize": 100,
      "pageNo": 2,
      "numOfRows": 100,
      "totalCount": 531,
      "actualCount": 100,
      "fetchedAt": "2026-09-09T01:00:43.647435+00:00"
    },
    {
      "scope": "NATIONWIDE",
      "requestedPage": 3,
      "requestedSize": 100,
      "pageNo": 3,
      "numOfRows": 100,
      "totalCount": 531,
      "actualCount": 100,
      "fetchedAt": "2026-09-09T01:00:44.393822+00:00"
    },
    {
      "scope": "NATIONWIDE",
      "requestedPage": 4,
      "requestedSize": 100,
      "pageNo": 4,
      "numOfRows": 100,
      "totalCount": 531,
      "actualCount": 100,
      "fetchedAt": "2026-09-09T01:00:45.107838+00:00"
    },
    {
      "scope": "NATIONWIDE",
      "requestedPage": 5,
      "requestedSize": 100,
      "pageNo": 5,
      "numOfRows": 100,
      "totalCount": 531,
      "actualCount": 100,
      "fetchedAt": "2026-09-09T01:00:45.879771+00:00"
    },
    {
      "scope": "NATIONWIDE",
      "requestedPage": 6,
      "requestedSize": 100,
      "pageNo": 6,
      "numOfRows": 100,
      "totalCount": 531,
      "actualCount": 31,
      "fetchedAt": "2026-09-09T01:00:46.640695+00:00"
    },
    {
      "scope": "NATIONWIDE",
      "requestedPage": 7,
      "requestedSize": 100,
      "pageNo": 7,
      "numOfRows": 100,
      "totalCount": 531,
      "actualCount": 0,
      "fetchedAt": "2026-09-09T01:00:47.343867+00:00"
    }
  ],
  "testedPageSizes": [
    {
      "requested": 100,
      "returned": 100,
      "actualCount": 100
    },
    {
      "requested": 500,
      "returned": 500,
      "actualCount": 500
    },
    {
      "requested": 1000,
      "returned": 1000,
      "actualCount": 531
    }
  ],
  "timezone": "UNVERIFIED",
  "maximumNumOfRows": "UNVERIFIED",
  "totalCount": 531,
  "uniqueHpidCount": 531,
  "observedAddressPrefixes": [
    "강원특별자치도",
    "경기도",
    "경상남도",
    "경상북도",
    "대구광역시",
    "대전광역시",
    "부산광역시",
    "서울특별시",
    "세종특별자치시",
    "울산광역시",
    "인천광역시",
    "전남광주통합특별시",
    "전북특별자치도",
    "제주특별자치도",
    "충청남도",
    "충청북도"
  ],
  "safePageSize": 100,
  "outOfRangeEmpty": true,
  "completedAt": "2026-09-09T01:00:48.037038+00:00"
}
```

A PASSED result validates only the observed request scope and safe page size, not a guaranteed global maximum or timestamp timezone.
