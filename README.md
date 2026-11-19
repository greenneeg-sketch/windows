# 유리창

우리 동네 어딘가에 서 있는 유리창에 포스트잇을 붙이고 가는 1인칭 3D 웹 공간입니다.

- 1인칭 시점으로 걸어서 창문 앞까지 가요 (조이스틱 / WASD, Space 점프, C 앉기)
- 내 위치에서 가까운 지역 창만 열려요 (서울 마포, 부산 해운대, 강원 강릉, 제주)
- 포스트잇에 손글씨나 그림을 그리고, 글자를 원하는 자리에 놓고 돌릴 수 있어요 (글씨체 6종)
- 내가 붙인 포스트잇은 수정하거나 떼어낼 수 있어요
- 욕설·링크·전화번호 필터, 신고 버튼, 하루 3장 제한

## 실행

정적 파일만으로 동작합니다. GitHub Pages에서 `main` 브랜치의 루트(`/`)를 배포하면 됩니다.
로컬에서는 `python3 -m http.server` 후 `http://localhost:8000` 으로 열어주세요.

## 현재 한계 (서버 연결 전)

- 포스트잇, 공감, 신고, 하루 제한은 지금은 각자 기기(localStorage)에만 저장됩니다.
- 실제 서비스에서는 서버(예: Supabase)에서 저장, 욕설 필터, 신고 누적 숨김, 하루 제한을 다시 검사해야 합니다.

## 사용한 에셋 (모두 CC0)

- 3D 모델: [Quaternius — Stylized Nature MegaKit](https://quaternius.com/packs/stylizednaturemegakit.html)
- 하늘 HDRI: [Poly Haven](https://polyhaven.com) (venice_sunset, dikhololo_night, kiara_1_dawn, rooitou_park)
- 창틀 텍스처: [ambientCG — Bark014](https://ambientcg.com/view?id=Bark014)
- 3D 엔진: [three.js](https://threejs.org) r128 (MIT)
- 글씨체: Google Fonts (나눔펜, 개구, 감자꽃, 하이멜로디, 주아, 고운바탕 — OFL)
