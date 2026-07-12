# Flutter Project Structure

## Rules

``` text
lib/
│
├── app/
│   └── router.dart
│
├── core/
│   ├── constants/
│   │   ├── colors.dart
│   │   ├── strings.dart
│   │   └── dimensions.dart
│   │
│   └── services/
│       ├── api_service.dart
│       ├── storage_service.dart
│       └── permission_service.dart
│
├── features/
│   ├── home/
│   │   ├── data/
│   │   ├── models/
│   │   ├── screens/
│   │   └── widgets/
│   │
│   ├── profile/
│   │   ├── data/
│   │   ├── models/
│   │   ├── screens/
│   │   └── widgets/
│   │
│   └── settings/
│       ├── data/
│       ├── models/
│       ├── screens/
│       └── widgets/
│
└── main.dart
```

## Guidelines

-   Each feature is self-contained.
-   `data/` contains repositories and API integrations.
-   `models/` contains model classes.
-   `screens/` contains page widgets.
-   `widgets/` contains reusable widgets for that feature.
-   `core/constants/` contains global constants.
-   `core/services/` contains shared services.
-   `app/router.dart` is the single source of truth for navigation.
-   `main.dart` is the application entry point.

