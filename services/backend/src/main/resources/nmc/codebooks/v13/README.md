# NMC V13 source hierarchy

`codebook.json` is the runtime interpretation allowlist. Every interpreted field has an endpoint, official label, PDF page and parser kind. Fields outside this list are retained as UNVERIFIED, never guessed. UNKNOWN_CODE preserves the original code.

The original PDF in docs/references is the official semantic source; docs/api/NMC_API_Data_Design_v0.2.md contains empirical observations. User-approved policy supersedes that document's older timezone/UI suggestions: no timezone conversion, and HVS01 is 일반 기준값 (official 일반_기준).

PDF p2 revision history ends 2026-08-27; the cover's internal version number is not used as the codebook version. SHA-256 pins the exact local V13 PDF. Reviewers can inspect this JSON without the PDF, but developers must run scripts/verify_sources.py before changing NMC interpretation. A changed PDF requires explicit re-review and a new hash; do not silently update the hash.

No fallback to basic hv*, no HVS occupancy denominator, no N1=false, no MKioskTy28 propagation. New semantics require field-specific evidence and regression tests.

The basic-info section is a weekly static cache, independently discovered and budgeted. The authenticated discovery report is `docs/api/nmc-basic-discovery-report.md`. The observed comma delimiter and literal department names are versioned in the normalization policy. Unknown names remain UNVERIFIED; raw occurrences and order are preserved. Strict HHmm pairs alone become intervals; 0000/2400 and reversed/equal pairs remain UNVERIFIED. Missing values are never filled from another day or endpoint. `dutyTel3` remains 대표전화2.

`semanticStatus`/PDF references establish the official field label. `normalizationPolicy` and discovery evidence establish how a value is interpreted. `dataType=XML_TEXT` describes the transport representation, not a numeric type promised by the PDF. The basic key is request `HPID`, response `hpid`; no global casing fold is performed. API presentation deduplicates department names, while normalized storage keeps raw token order and duplicates.
