# Qualcomm Hackathon - Glasses Assistant Architecture & Features Guide

## 📋 Table of Contents
1. [Project Overview](#project-overview)
2. [Features Added](#features-added)
3. [Architecture Overview](#architecture-overview)
4. [Component Flow & Class Relationships](#component-flow--class-relationships)
5. [Detailed Component Descriptions](#detailed-component-descriptions)
6. [Feature Implementations](#feature-implementations)
7. [Data Flow Diagrams](#data-flow-diagrams)

---

## Project Overview

This is a **Flutter-based AI Assistant for Meta Ray-Ban Smart Glasses** built during a Qualcomm hackathon. The application provides an on-device voice interface that captures audio through the glasses, processes it locally using a lightweight LLM (Llama), and responds through text-to-speech.

**Key Characteristics:**
- **On-Device Processing**: All AI inference runs locally on the device (using fllama)
- **Low Latency**: Optimized for real-time interaction with wearable glasses
- **Voice-First Interface**: Primary interaction through natural language
- **Extensible Architecture**: Easy to add new features through the Feature Executor pattern
- **Personalization**: On-device memory store for user preferences and remembered information

---

## Features Added

### 1. **Glasses Voice Assistant** ✨ (NEW)
Complete end-to-end voice pipeline for Meta Ray-Ban Smart Glasses:
- Real-time audio capture from glasses microphone
- Speech-to-Text conversion using Whisper
- Intent extraction and response generation via on-device LLM
- Text-to-Speech playback through glasses speaker
- Connection status monitoring and user feedback
- State machine-driven pipeline with visual feedback (animated orb)

**Related Classes:**
- `GlassesAssistantPipeline` - Main orchestrator
- `GlassesVoiceScreen` - UI surface with connection banner and transcript display
- `PipelineOrb` - Animated visual indicator of pipeline phase

### 2. **Memory System** 🧠 (NEW)
Remember and recall facts on-device with semantic matching:
- **Remember** custom information ("remember my parking spot is level 3")
- **Recall** remembered information with fuzzy topic matching
- Context-aware retrieval (only relevant entries injected into prompts)
- Cross-store fallback (searches both memory topics and legacy checklists)

**Related Classes:**
- `MemoryStore` - Core in-memory store for remembered entries
- `RememberTopicExecutor` - Handles "remember this" intents
- `RecallTopicExecutor` - Handles "recall this" intents
- `MemoriesScreen` - Browse all remembered items

### 3. **Intent-Based Command System** 🎯 (ENHANCED)
Flexible feature execution based on AI-detected intent:
- Model automatically classifies user intent from natural language
- Features execute based on intent, not hard-coded UI flows
- Graceful fallbacks for unrecognized intents
- No executor required — can use template-based replies

**Related Classes:**
- `FeatureExecutor` - Abstract base for feature handlers
- `FeatureExecutors` - Registry for intent → executor mapping
- `HomeRepository` - Command orchestration and fallback logic

### 4. **LLM Model Management** 📦 (ENHANCED)
Simplified on-device model download and lifecycle:
- Check for existing downloaded model at startup
- Download from cloud if needed
- Verify file integrity
- Warm up model before first use (pre-load weights)

**Related Classes:**
- `LlmDownloadRepository` - Model download and storage
- `LlmModel` - Model metadata (size, version, local path)
- `FileDownloadService` - HTTP download with progress tracking
- `DownloadLlmScreen` - Download progress UI

### 5. **Local Data Storage** 💾 (CORE)
Persistent on-device storage for user information:
- Checklists and to-do lists
- Saved preferences and favorites
- Meeting transcripts and notes
- Legacy intent-based storage system

**Related Classes:**
- `LocalDataStore` - Main storage service
- `StorageService` - Low-level persistent storage

### 6. **Adaptive Response Generation** 🎨 (ENHANCED)
Smart message formatting for glasses display:
- Intent-aware message templates via `GlassesMessageBuilder`
- Optional LLM rewriting for natural speech
- Server fallback for low-confidence intents
- Time/date resolution for human-readable formats

**Related Classes:**
- `GlassesMessageBuilder` - Template-based response formatting
- `TimeResolver` - Convert time parameters to natural language

### 7. **Stub Features** (Framework Ready) 🔄
The architecture supports adding these features with minimal code:
- **RAG Query** - Vector search over knowledge base (executor exists, data source needed)
- **OCR Reading** - Extract text from camera frames (executor exists, ML Kit integration needed)
- **Geolocation** - Query current location (executor exists, platform APIs needed)

**Related Classes:**
- `RagQueryExecutor` - Placeholder for RAG queries
- `OcrReadTextExecutor` - Placeholder for OCR reading
- `QueryLocationExecutor` - Placeholder for location queries

---

## Architecture Overview

### High-Level Structure

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter App                           │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌──────────────────────────────────────────────────┐  │
│  │           Features Layer (UI + Logic)            │  │
│  │                                                   │  │
│  │  • GlassesVoiceScreen    (Voice interface)       │  │
│  │  • HomeScreen            (Text/command interface)│  │
│  │  • MemoriesScreen        (Browse memories)       │  │
│  │  • DownloadLlmScreen     (Model management)      │  │
│  │                                                   │  │
│  └──────────────────────────────────────────────────┘  │
│                           △                              │
│                           │                              │
│  ┌──────────────────────────────────────────────────┐  │
│  │         Data Layer (Repositories & Services)     │  │
│  │                                                   │  │
│  │  • HomeRepository        (Command orchestration) │  │
│  │  • GlassesAssistantPipeline (Voice orchestration)│  │
│  │  • LlmDownloadRepository (Model lifecycle)       │  │
│  │                                                   │  │
│  └──────────────────────────────────────────────────┘  │
│                           △                              │
│                           │                              │
│  ┌──────────────────────────────────────────────────┐  │
│  │            Core Services Layer                   │  │
│  │                                                   │  │
│  │  • AiService            (LLM inference)          │  │
│  │  • MemoryStore          (On-device memory)       │  │
│  │  • LocalDataStore       (Persistent storage)     │  │
│  │  • FeatureExecutors     (Intent handlers)        │  │
│  │  • FileDownloadService  (Model downloads)        │  │
│  │  • StorageService       (File I/O)               │  │
│  │                                                   │  │
│  └──────────────────────────────────────────────────┘  │
│                           △                              │
│                           │                              │
│  ┌──────────────────────────────────────────────────┐  │
│  │         Hardware/Plugin Layer                    │  │
│  │                                                   │  │
│  │  • MetaWearablesAudio   (Glasses mic/speaker)   │  │
│  │  • MetaWearablesCamera  (Glasses camera)        │  │
│  │  • WhisperSpeechToText  (Audio → text)          │  │
│  │  • FlutterTtsSpeech     (Text → audio)          │  │
│  │                                                   │  │
│  └──────────────────────────────────────────────────┘  │
│                           △                              │
└───────────────────────────┼───────────────────────────┘
                            │
                    Hardware/OS APIs
                    (Android/iOS/Linux)
```

### Layered Architecture Principles

- **UI Layer**: Flutter screens and widgets - zero business logic
- **Data Layer**: Repositories orchestrate services and coordinate features
- **Service Layer**: Core functionality (AI, storage, downloads, features)
- **Hardware Layer**: Native plugins abstracting device APIs
- **Dependency Injection**: Services typically use singletons (`.instance`) for global access

---

## Component Flow & Class Relationships

### 1. Application Startup Flow

```
main()
  ↓
MyApp (StatefulWidget)
  ↓
_MyAppState.initState()
  ├─ _determineInitialRoute()
  │   ├─ LlmDownloadRepository.init()
  │   ├─ LlmDownloadRepository.getSavedModel()
  │   └─ Check if File exists
  │       ├─ Yes → Route '/glasses'
  │       └─ No  → Route '/download-model'
  │
  └─ FutureBuilder renders initial screen
      ├─ DownloadLlmScreen (if model missing)
      └─ GlassesVoiceScreen (if model ready)
```

**Key Decision Point**: The app decides at startup whether to show the download screen or the voice interface based on:
1. Whether a model has been downloaded and saved locally
2. Whether the file still exists at the saved path

---

### 2. Voice Pipeline Flow (Glasses Interface)

```
GlassesVoiceScreen.build()
  │
  ├─ Renders connection banner (_ConnectionBanner)
  │   └─ Shows camera + audio connection status
  │
  ├─ Renders animated orb (PipelineOrb)
  │   └─ Visual feedback: idle → listening → thinking → speaking
  │
  ├─ Renders transcript bubbles
  │   ├─ User's spoken words (right-aligned)
  │   └─ Assistant's response (left-aligned)
  │
  └─ Button: "Ask the glasses"
      └─ Triggers GlassesAssistantPipeline.runTurn()


GlassesAssistantPipeline.runTurn() — Main Voice Flow:

1. Listen Phase
   ├─ MetaWearablesAudio.startListening()
   ├─ Capture audio frames at 8kHz mono
   ├─ Wait for speech start (5s timeout)
   └─ Wait for silence (1.2s timeout or 15s max)

2. Transcribe Phase
   ├─ WhisperSpeechToText.transcribe(pcmBuffer)
   └─ Get text transcript from audio

3. Thinking Phase
   ├─ HomeRepository.runExtraction(transcript)
   │   ├─ AiService.extract() — intent classification
   │   ├─ AiService.extract() — parameter extraction
   │   ├─ FeatureExecutors.forIntent() — find handler
   │   │
   │   ├─ If executor exists:
   │   │   └─ executor.execute() → glassesMessage
   │   │
   │   └─ Else:
   │       ├─ LocalDataStore.applyStorageSideEffects()
   │       ├─ GlassesMessageBuilder.build() → template
   │       └─ Optional: AiService.polishGlassesReply() → natural speech
   │
   └─ Get response string

4. Speak Phase
   ├─ FlutterTtsSpeech.speak(glassesMessage)
   └─ Play audio through glasses speaker

5. Idle Phase
   └─ Ready for next turn
```

---

### 3. Text Interface Flow (Home Screen)

```
HomeScreen
  │
  └─ Text input + "Send" button
      │
      └─ HomeRepository.runExtraction(userText)
          │
          └─ Same as voice pipeline thinking phase
              ├─ Intent classification
              ├─ Parameter extraction
              ├─ Feature executor OR template builder
              └─ Return response
          │
          └─ ExtractionResultCard
              ├─ Show intent + confidence
              ├─ Show parameters
              ├─ Show final response
              └─ Optional: side effects already applied
```

---

### 4. Memory System Flow

```
User: "Remember my parking spot is level 3"
  │
  └─ GlassesAssistantPipeline.runTurn()
      │
      └─ HomeRepository.runExtraction()
          │
          ├─ AiService.extract()
          │   └─ Classifies intent: "remember_topic_v1"
          │   └─ Extracts: {topic: "parking spot", content: "level 3"}
          │
          ├─ FeatureExecutors.forIntent("remember_topic_v1")
          │   └─ Returns RememberTopicExecutor instance
          │
          └─ RememberTopicExecutor.execute()
              │
              └─ MemoryStore.remember(
                   topic: "parking spot",
                   content: "level 3",
                   tag: "remember_topic_v1"
                 )
              │
              └─ Returns: "Okay, I'll remember your parking spot."


User: "What's my parking spot?"
  │
  └─ GlassesAssistantPipeline.runTurn()
      │
      └─ HomeRepository.runExtraction()
          │
          ├─ AiService.extract()
          │   └─ Classifies intent: "recall_topic_v1"
          │   └─ Extracts: {topic: "parking spot"}
          │
          ├─ FeatureExecutors.forIntent("recall_topic_v1")
          │   └─ Returns RecallTopicExecutor instance
          │
          └─ RecallTopicExecutor.execute()
              │
              ├─ MemoryStore.recall("parking spot")
              │   └─ Returns MemoryEntry with content
              │
              └─ AiService.groundedAnswer(
                   question: "What's my parking spot?",
                   grounding: "level 3"
                 )
              │
              └─ Returns: "Your parking spot is on level 3."
```

---

### 5. Model Lifecycle

```
App Launch
  │
  └─ main() → MyApp._MyAppState.initState()
      │
      └─ _determineInitialRoute()
          │
          ├─ Model exists? YES → Route to /glasses
          │
          └─ Model missing? → Route to /download-model
              │
              └─ DownloadLlmScreen
                  │
                  ├─ Show available models
                  ├─ User selects model
                  │
                  └─ LlmDownloadRepository.downloadModel()
                      │
                      ├─ FileDownloadService.download()
                      │   └─ HTTP download with progress
                      │
                      ├─ Verify file integrity
                      │
                      └─ Save metadata to storage
                          │
                          └─ Ready to use!
                              │
                              └─ Navigate to /glasses


First Voice Turn
  │
  └─ GlassesVoiceScreen (on load)
      │
      ├─ HomeRepository.ensureModelLoaded()
      │   │
      │   ├─ AiService.init(modelPath)
      │   │   └─ Set _modelPath
      │   │
      │   └─ AiService.warmUp()
      │       └─ Run tiny inference to:
      │           ├─ Load weights into memory
      │           ├─ Allocate KV cache
      │           └─ Pre-compile kernels
      │
      └─ Ready for inference! (~30s on first call, but we pre-warmed)
```

---

## Detailed Component Descriptions

### **Core Services**

#### AiService
**File**: `lib/core/services/ai_service.dart`

The single entry point for all on-device LLM inference. Uses fllama (Llama.cpp Dart binding) to run inference locally.

**Key Methods:**
- `init(modelPath)` - Initialize with downloaded model
- `warmUp()` - Pre-load model and allocate cache (idempotent)
- `extract(transcript, knownLocalDataHint)` - Two-stage extraction:
  - Stage 1: Classify intent (e.g., "remember_topic_v1")
  - Stage 2: Extract parameters for that intent (e.g., {topic, content})
- `groundedAnswer(question, data)` - Answer question using provided context
- `polishGlassesReply(transcript, draftReply)` - Rephrase template into natural speech
- `rawChat(prompt, systemPrompt)` - Raw LLM call (for testing/custom logic)

**Configuration:**
- `interactiveContextSize = 1024` tokens - Context window size for all hot paths
- `_numGpuLayers = 99` - GPU offload (honored on Metal/Vulkan, CPU-only on Android)
- `_numThreads = Platform.numberOfProcessors - 2` - CPU threading (clamped 2-6)

**Usage Example:**
```dart
final aiService = AiService.instance;
await aiService.init('/path/to/model.gguf');
await aiService.warmUp();

final result = await aiService.extract(
  transcript: "Remember to call mom tomorrow at 5pm",
  knownLocalDataHint: "lists: shopping, groceries | topics: calls, reminders",
);
// Result: {intent: "remember_topic_v1", parameters: {topic: "call mom", time: {...}}}
```

---

#### MemoryStore
**File**: `lib/core/services/memory_store.dart`

In-memory personalization store for the remember/recall feature. Implements "store broadly, retrieve narrowly" principle.

**Key Methods:**
- `remember(topic, content, tag)` - Write one memory entry (overwrites duplicates)
- `recall(topic)` - Retrieve by exact topic match
- `retrieveRelevant(query, topK=3, byteBudget=512)` - Retrieve top-K entries by token similarity
- `forget(topic)` - Delete one entry
- `topicNames()` - Get all topic names (used for "known local data" hint)
- `allEntries()` - Full snapshot (UI-only, newest first)

**Data Structure:**
```dart
MemoryEntry {
  String topic;           // Normalized (lowercase, trimmed)
  String content;         // What to remember
  String tag;             // Which feature created it (for filtering)
  DateTime createdAt;     // When it was stored
}
```

**Context Budgeting:**
- Each entry estimated at `'$topic: $content'.length` bytes
- Retrieval capped by both count (K) and byte budget
- Ensures model prompts never bloat with full history

**Note**: Currently in-memory; ready to swap backing store for SQLite/Realm without changing the interface.

---

#### LocalDataStore
**File**: `lib/core/services/local_data_store.dart`

Persistent storage for legacy intents (checklists, preferences, meeting notes). Backed by `StorageService` (file-based JSON).

**Key Methods:**
- `applyStorageSideEffects(intent, parameters)` - Handle storage mutations for non-executor intents
- `lookupStored(queryType, reference)` - Retrieve data by category + name
- `lookupFuzzy(query)` - Fuzzy search by token overlap
- `buildKnownLocalDataHint()` - List all stored list/preference names for the model
- `storeList(name, items)`, `storePreference(name, value)` - Write data
- `storeMeetingSummary(name, lines)` - Store meeting transcript summary

**Usage Example:**
```dart
final store = LocalDataStore.instance;

// Write
await store.storeList("groceries", ["milk", "eggs", "bread"]);

// Read
final list = store.lookupStored(queryType: "list", reference: "groceries");
// Result: StoredData {name: "groceries", items: ["milk", "eggs", "bread"]}
```

---

#### FileDownloadService
**File**: `lib/core/services/file_download_service.dart`

HTTP download with progress tracking and retry logic. Used for model downloads.

**Key Methods:**
- `downloadFile(url, targetPath, onProgress)` - Download with progress callback
  - Callback receives `DownloadProgress {downloaded, total}` (in bytes)
  - Supports resume on partial downloads
  - Auto-creates parent directories

**Usage Example:**
```dart
final service = FileDownloadService();
await service.downloadFile(
  'https://cdn.example.com/model.gguf',
  '/local/path/model.gguf',
  onProgress: (progress) {
    print('${progress.downloaded}/${progress.total} bytes');
  },
);
```

---

### **Repositories (Data + Orchestration)**

#### HomeRepository
**File**: `lib/features/home/data/home_repository.dart`

High-level command orchestration. Ties together AiService, storage, memory, and executors into a cohesive "run a command" interface.

**Key Methods:**
- `ensureModelLoaded()` - Idempotent: verify model is loaded and warmed up
- `runExtraction(transcript)` - Main command pipeline:
  1. Extract intent + parameters from transcript
  2. Look up feature executor
  3. Confidence gate (fallback to server if too low)
  4. Execute feature OR apply side effects + format response
  5. Return `HomeExtractionView` with full context
- `answerFromStoredData(question, queryType, reference)` - Grounded answer
- `summarizeAndStoreMeeting(meetingName)` - Save meeting transcript

**Configuration:**
- `llmPhrasedReplies` (default true) - Rewrite template replies with LLM for natural speech

**Flow Diagram:**
```
runExtraction(transcript)
  │
  ├─ ensureModelLoaded()
  │
  ├─ AiService.extract(transcript, knownLocalDataHint)
  │   └─ Returns: ExtractionResult {intent, parameters, confidence, raw}
  │
  ├─ FeatureExecutors.forIntent(intent)
  │   └─ Look up handler for this intent
  │
  ├─ Confidence gate?
  │   ├─ Too low → ServerLlmService.respond() (fallback)
  │   └─ OK → Continue
  │
  ├─ Executor exists?
  │   ├─ Yes → executor.execute(result, transcript)
  │   │   └─ Feature handles everything (like recall_topic_v1)
  │   │
  │   └─ No → Legacy path:
  │       ├─ LocalDataStore.applyStorageSideEffects()
  │       ├─ GlassesMessageBuilder.build(intent, parameters)
  │       └─ Optional: AiService.polishGlassesReply()
  │
  └─ Return HomeExtractionView {transcript, intent, parameters, confidence, glassesMessage}
```

---

#### LlmDownloadRepository
**File**: `lib/features/download_llm_model/data/llm_download_repository.dart`

Model lifecycle management: fetch list, download, verify, store metadata.

**Key Methods:**
- `init()` - Load stored model metadata (if any)
- `fetchAvailableModels()` - List downloadable models (currently hardcoded)
- `getSavedModel()` - Get metadata of previously downloaded model
- `downloadAndSaveModel(model, onProgress)` - Download and store
  - Uses FileDownloadService
  - Saves metadata + local path
  - Verifies file exists before returning success

**Data Model:**
```dart
LlmModel {
  String name;           // Display name
  String version;        // Version identifier
  String? downloadUrl;   // Where to fetch
  int? sizeInBytes;      // Expected size
  bool isDownloaded;     // Locally available?
  String? localPath;     // Where it's stored
}
```

---

#### GlassesAssistantPipeline
**File**: `lib/features/glasses_voice/data/glasses_pipeline.dart`

State machine orchestrating the complete voice conversation: listen → transcribe → think → speak → idle.

**Key Methods:**
- `runTurn()` - Execute one full conversation turn
  1. Emit `listening` phase
  2. Capture audio until silence
  3. Emit `thinking` phase
  4. Transcribe + run extraction
  5. Emit `speaking` phase
  6. Play response
  7. Emit `idle` phase
- `states` - Stream of `PipelineState` for UI updates

**Configuration (Audio):**
- Sample rate: 8 kHz mono (HFP mic limitation)
- Speech start timeout: 5 seconds
- Silence timeout: 1.2 seconds
- Max listen duration: 15 seconds
- Speech threshold: 350 (energy level)

**PipelineState:**
```dart
PipelineState {
  PipelinePhase phase;   // idle, listening, thinking, speaking, error
  String? transcript;    // Best-known user's words
  String? reply;         // Best-known response
  Object? error;         // Exception if phase == error
}
```

---

### **Feature Executors (Intent Handlers)**

#### FeatureExecutor (Abstract)
**File**: `lib/core/features/feature_executor.dart`

Base class for all feature-specific intent handlers.

```dart
abstract class FeatureExecutor {
  String get featureId;  // Maps to intent name (e.g., "remember_topic_v1")
  
  Future<String> execute(
    ExtractionResult result,
    {required String transcript},
  );  // Returns spoken reply
}
```

---

#### RememberTopicExecutor
Handles intent `remember_topic_v1`. Extracts `{topic, content}` and stores.

```dart
// User: "Remember my parking spot is level 3"
// Extracted: {topic: "parking spot", content: "level 3"}
// Result: "Okay, I'll remember your parking spot."
// Side effect: MemoryStore.remember("parking spot", "level 3", ...)
```

---

#### RecallTopicExecutor
Handles intent `recall_topic_v1`. Retrieves and phrases response with context.

```dart
// User: "What's my parking spot?"
// Extracted: {topic: "parking spot"}
// Lookup: MemoryStore.recall("parking spot")
// Result: AiService.groundedAnswer("...", "level 3")
// → "Your parking spot is on level 3."
```

---

#### RecallStoredInfoExecutor
Handles intent `recall_stored_info_v1`. Unifies recall from MemoryStore and LocalDataStore.

```dart
// User: "What's on my shopping list?"
// Lookup: LocalDataStore.lookupFuzzy("shopping list")
// Result: AiService.groundedAnswer("...", {name: "shopping", items: [...]})
```

---

#### Stub Executors (Framework Ready)
- **RagQueryExecutor** - Placeholder for vector search
- **OcrReadTextExecutor** - Placeholder for camera text extraction
- **QueryLocationExecutor** - Placeholder for geolocation

Each has the full executor interface; replace the `execute` body with real logic.

---

### **UI Components**

#### GlassesVoiceScreen
**File**: `lib/features/glasses_voice/screens/glasses_voice_screen.dart`

Main voice interface with four visual sections:

1. **Connection Banner** (`_ConnectionBanner`)
   - Shows camera + audio connection status
   - Displays audio route (HFP mic/speaker, A2DP speaker, etc.)
   - Offers "Connect" or "Retry" button if disconnected

2. **Animated Orb** (`PipelineOrb`)
   - Color and animation reflect pipeline phase
   - idle → gray, listening → blue, thinking → orange, speaking → green, error → red

3. **Conversation Bubbles** (`_SpeechBubble`)
   - Right-aligned: user's transcript ("YOU")
   - Left-aligned: assistant's reply ("ASSISTANT")
   - Scroll history as new turns arrive

4. **Error Card** (`_ErrorCard`)
   - Large, visible error display (not transient snackbar)
   - Shows phase-appropriate error color

5. **Control Row** (`_DeviceControls`)
   - "Ask the glasses" button → triggers `pipeline.runTurn()`
   - "Start stream" / "Stop stream" for camera (dev controls)

**Flow:**
```dart
class _GlassesVoiceScreenState extends State<GlassesVoiceScreen> {
  @override
  void initState() {
    // Pre-load model in background while user connects glasses
    HomeRepository().ensureModelLoaded();
    
    // Subscribe to pipeline state updates
    _pipelineSub = _pipeline.states.listen((state) {
      setState(() => _pipelineState = state);
    });
  }
  
  Future<void> _run(Future<void> Function() action) {
    // Execute action with busy state + error handling
  }
  
  @override
  Widget build(BuildContext context) {
    // Render UI based on _pipelineState
  }
}
```

---

#### HomeScreen
**File**: `lib/features/home/screens/home_screen.dart`

Text-based interface for testing commands without glasses.

- Text input field
- "Send" button → `HomeRepository.runExtraction(text)`
- ExtractionResultCard displaying response

---

#### MemoriesScreen
**File**: `lib/features/memories/screens/memories_screen.dart`

Browse and delete remembered items.

- List of all MemoryStore entries (newest first)
- Delete button per item
- Empty state message

---

#### DownloadLlmScreen
**File**: `lib/features/download_llm_model/screens/download_llm_screen.dart`

Model selection and download interface.

- List of available models
- DownloadProgressWidget with progress bar + percentage
- Auto-navigate to voice screen when complete

---

### **Plugins & Hardware Adapters**

#### flutter_meta_wearables_dat Plugin
**Path**: `plugins/flutter_meta_wearables_dat/`

Custom Flutter plugin encapsulating Meta's DAT (Direct Access Toolkit) camera API and Bluetooth audio APIs.

**Dart Exports:**
- `MetaWearablesCamera` - Camera stream API
- `MetaWearablesAudio` - Mic/speaker API
- `GlassesVideoFrame`, `GlassesPhoto` - Camera data types
- `GlassesAudioChunk`, `GlassesAudioState` - Audio data types

**Android Native (Kotlin):**
- `GlassesCameraManager` - Wraps Meta DAT API
  - `AutoDeviceSelector` - Pick first connected device
  - `Stream<GlassesVideoFrame>` - Continuous video
  - `capturePhoto()` - Single still
  
- `GlassesAudioManager` - Manages mic/speaker audio modes
  - HFP/SCO (8 kHz mono bidirectional) for mic capture
  - A2DP (44.1/48 kHz stereo output-only) for speaker
  - Audio modes mutually exclusive on BT Classic link
  - `startListening()` / `stopListening()` - Switch to HFP
  - `speak(audioBytes)` - Play via A2DP

**iOS Native (Swift):**
- Stubs (DAT and high-bandwidth audio APIs iOS-only on Meta ecosystem)

---

#### WhisperSpeechToText
**File**: `lib/features/glasses_voice/data/whisper_speech_to_text.dart`

Speech-to-text abstraction. Currently a stub returning mock data in-development.

**Interface:**
```dart
abstract class SpeechToText {
  Future<String> transcribe(Uint8List pcmAudio, int sampleRate);
}

class WhisperSpeechToText implements SpeechToText {
  // Real version: call on-device Whisper via fllama or separate binary
  // For now: return mock transcript
}
```

---

#### FlutterTtsSpeech
**File**: `lib/features/glasses_voice/data/voice_providers.dart`

Text-to-speech abstraction using flutter_tts plugin.

**Interface:**
```dart
abstract class TextToSpeech {
  Future<void> speak(String text);
  Future<void> stop();
}

class FlutterTtsSpeech implements TextToSpeech {
  // Uses flutter_tts plugin
  // Configurable rate, pitch, language
}
```

---

## Feature Implementations

### Feature 1: Voice Pipeline (Glasses Interface)

**Files Involved:**
- Screen: `GlassesVoiceScreen`
- Orchestrator: `GlassesAssistantPipeline`
- Data: `HomeRepository`
- AI: `AiService`
- Hardware: `MetaWearablesAudio`, `MetaWearablesCamera`

**How It Works:**

1. User taps "Ask the glasses"
2. GlassesVoiceScreen calls `pipeline.runTurn()`
3. GlassesAssistantPipeline:
   - Emits `listening` phase
   - Calls `MetaWearablesAudio.startListening()` → captures 8kHz mono PCM
   - Waits for speech + silence
   - Emits `thinking` phase
   - Calls `WhisperSpeechToText.transcribe()` → text
   - Calls `HomeRepository.runExtraction(text)` → response
   - Emits `speaking` phase
   - Calls `FlutterTtsSpeech.speak(response)` → plays audio
   - Emits `idle` phase
4. Each phase emission triggers UI update via stream
5. UI shows transcript, reply, phase, and any errors

**Key Innovation: Injected Dependencies**
All I/O is swappable (STT, TTS, audio hardware). Test with different implementations without changing pipeline code.

---

### Feature 2: Memory System (Remember/Recall)

**Files Involved:**
- Data: `MemoryStore`
- Executors: `RememberTopicExecutor`, `RecallTopicExecutor`
- UI: `MemoriesScreen`
- Hints: `HomeRepository._buildKnownLocalDataHint()`

**How It Works:**

1. User says "Remember my parking spot is level 3"
2. HomeRepository extracts intent + parameters
3. Looks up RememberTopicExecutor
4. Executor calls `MemoryStore.remember(topic, content, tag)`
5. MemoryStore stores entry with normalized key + timestamp

**Retrieval (Recall):**

1. User says "What's my parking spot?"
2. HomeRepository extracts intent + parameters
3. Looks up RecallTopicExecutor
4. Executor calls `MemoryStore.recall(topic)` → MemoryEntry
5. Executor calls `AiService.groundedAnswer(question, entry.content)` → natural response

**Scaling Rules:**

1. **Tag at write time** - Every entry tagged with feature id (e.g., "remember_topic_v1"). Allows future filtering by category.
2. **Retrieve narrowly** - Never inject full store into prompts. Use exact match (recall) or top-K by similarity (retrieveRelevant). Always cap bytes.
3. **Degrade gracefully** - If topic missing, fallback to LocalDataStore search (legacy lists/prefs). If still missing, return helpful "nothing saved" message, not improvisation.

---

### Feature 3: Intent-Based Command System

**Files Involved:**
- Core: `FeatureExecutor`, `FeatureExecutors`
- Executors: `RememberTopicExecutor`, `RecallTopicExecutor`, `RagQueryExecutor`, etc.
- Orchestration: `HomeRepository`
- AI: `AiService`

**How It Works:**

1. **Intent Classification** (`AiService.extract` stage 1)
   - Prompt: "What intent does this transcript express?"
   - Model classifies: "remember_topic_v1", "recall_topic_v1", etc.

2. **Parameter Extraction** (`AiService.extract` stage 2)
   - Prompt: "[Feature-specific extraction prompt]"
   - Model extracts parameters for that intent

3. **Executor Lookup** (`FeatureExecutors.forIntent`)
   - Does an executor exist for this intent?
   - If yes: call `executor.execute(result, transcript)` → full control
   - If no: fall through to legacy path (template + optional polish)

4. **Feature Executor** (e.g., RememberTopicExecutor)
   - Fully owns the response
   - May call AiService for grounded answers
   - May call storage services for side effects
   - Returns final natural-language reply

**Extensibility:**
Adding a new feature is a 3-step process:

1. Add AiManifests entry (intent name + extraction prompt)
2. Create FeatureExecutor subclass
3. Register in `FeatureExecutors._byId` map

No changes to AiService, parameter normalizer, or model download needed.

---

### Feature 4: LLM Model Management

**Files Involved:**
- Download: `LlmDownloadRepository`, `FileDownloadService`
- Storage: `StorageService`, `LlmModel`
- Initialization: `HomeRepository.ensureModelLoaded()`, `AiService.warmUp()`
- UI: `DownloadLlmScreen`, `DownloadProgressWidget`

**How It Works:**

1. **On App Launch** (`MyApp._determineInitialRoute`)
   - Check `LlmDownloadRepository.getSavedModel()`
   - If exists + file accessible: route to `/glasses`
   - Else: route to `/download-model`

2. **Download Screen** (`DownloadLlmScreen`)
   - Shows list of models
   - User selects model
   - Calls `LlmDownloadRepository.downloadAndSaveModel()`
   - FileDownloadService streams bytes + calls progress callback
   - DownloadProgressWidget updates progress bar
   - Saves model metadata + local path
   - Auto-navigates to voice screen

3. **First Voice Turn** (`GlassesVoiceScreen.initState`)
   - Calls `HomeRepository.ensureModelLoaded()`
   - AiService.init(modelPath) → load weights
   - AiService.warmUp() → run tiny inference to pre-allocate cache
   - ~30s delay absorbed by loading UI
   - No user-visible stall on first real query

---

## Data Flow Diagrams

### Complete Voice Turn Flow

```
User: "Remind me to water the plants tomorrow at 10am"
│
└─ GlassesVoiceScreen → pipeline.runTurn()
   │
   ├─ LISTEN PHASE
   │  └─ MetaWearablesAudio.startListening()
   │     └─ PCM buffer: [8000 samples @ 8kHz mono]
   │
   ├─ TRANSCRIBE PHASE
   │  └─ WhisperSpeechToText.transcribe(pcmBuffer)
   │     └─ transcript: "Remind me to water the plants tomorrow at 10am"
   │
   ├─ THINK PHASE (HomeRepository.runExtraction)
   │  │
   │  ├─ AiService.extract (Stage 1: Intent)
   │  │  ├─ Input: transcript + knownLocalDataHint
   │  │  └─ Output: intent = "create_reminder_v1"
   │  │
   │  ├─ AiService.extract (Stage 2: Parameters)
   │  │  ├─ Input: transcript + intent-specific prompt
   │  │  └─ Output: {
   │  │       title: "water the plants",
   │  │       time: {unit: "hour", value: 10, date: "2024-07-15"}
   │  │     }
   │  │
   │  ├─ FeatureExecutors.forIntent("create_reminder_v1")
   │  │  └─ No executor → falls through to legacy path
   │  │
   │  ├─ LocalDataStore.applyStorageSideEffects("create_reminder_v1", params)
   │  │  └─ Stores reminder internally
   │  │
   │  ├─ TimeResolver.resolve({unit: "hour", value: 10, ...})
   │  │  └─ humanTime: "10:00 AM tomorrow"
   │  │
   │  ├─ GlassesMessageBuilder.build("create_reminder_v1", params, humanTime)
   │  │  └─ template: "Okay, I'll remind you to water the plants tomorrow at 10:00 AM."
   │  │
   │  └─ AiService.polishGlassesReply(transcript, template)
   │     └─ polished: "Got it, I'll remind you to water the plants tomorrow morning at 10 AM."
   │
   ├─ SPEAK PHASE
   │  └─ FlutterTtsSpeech.speak("Got it, I'll remind you...")
   │     └─ Audio plays through glasses speaker
   │
   └─ IDLE PHASE
      └─ Ready for next turn
```

---

### Intent Extraction with Feature Executor

```
User: "Remember my favorite coffee is oat milk lattes"
│
└─ AiService.extract(transcript, knownLocalDataHint)
   │
   ├─ Stage 1: Intent Classification
   │  ├─ Prompt:
   │  │   "Classify the intent: 'Remember my favorite coffee is oat milk lattes'"
   │  │   "Intent options: remember_topic_v1, recall_topic_v1, ..."
   │  │
   │  └─ Model output: "remember_topic_v1"
   │
   ├─ Stage 2: Parameter Extraction
   │  ├─ Prompt (remember_topic_v1 specific):
   │  │   "Extract topic and content from: 'Remember my favorite coffee is oat milk lattes'"
   │  │   "Topic should be brief. Content is detailed."
   │  │
   │  └─ Model output:
   │      {
   │        topic: "favorite coffee",
   │        content: "oat milk lattes"
   │      }
   │
   └─ Return ExtractionResult:
      {
        intent: "remember_topic_v1",
        parameters: {topic: "favorite coffee", content: "oat milk lattes"},
        confidence: 0.94,
        raw: "[raw model response]"
      }

HomeRepository.runExtraction() continues:
│
├─ FeatureExecutors.forIntent("remember_topic_v1")
│  └─ Returns: RememberTopicExecutor instance
│
└─ RememberTopicExecutor.execute(result, transcript)
   │
   ├─ Extract topic + content from result.parameters
   │
   ├─ MemoryStore.remember(
   │    topic: "favorite coffee",
   │    content: "oat milk lattes",
   │    tag: "remember_topic_v1"
   │  )
   │
   └─ Return: "Okay, I'll remember your favorite coffee."
```

---

### Server Fallback Flow (Low Confidence)

```
User: "Blah blah nonsense"
│
└─ AiService.extract → {intent: "unknown", confidence: 0.15}
   │
   ├─ Confidence < threshold (0.5)?
   │  └─ YES → Fallback to server
   │
   └─ HomeRepository._serverLlmGate.shouldFallback(0.15)
      └─ YES
      │
      └─ ServerLlmService.respond(
           ServerLlmRequest {
             transcript: "Blah blah nonsense",
             localIntent: "unknown",
             localConfidence: 0.15,
           }
         )
      │
      └─ [Server LLM stub returns generic response]
         │
         └─ HomeExtractionView {
              transcript: "Blah blah nonsense",
              glassesMessage: "I didn't understand that. Can you say it differently?",
              usedServerFallback: true
            }
```

---

### Memory Storage & Retrieval

```
WRITE:
User: "Remember my password hint is fluffy cat"
│
└─ RememberTopicExecutor.execute()
   └─ MemoryStore.remember(
        topic: "password hint",        // normalized → "password hint"
        content: "fluffy cat",
        tag: "remember_topic_v1",
        createdAt: DateTime.now()
      )
      │
      └─ Internal: _entries["password hint"] = MemoryEntry(...)


RETRIEVE (Exact):
User: "What's my password hint?"
│
└─ RecallTopicExecutor.execute()
   └─ MemoryStore.recall("password hint")
      │
      ├─ Normalize input → "password hint"
      ├─ Look up _entries["password hint"]
      └─ Return MemoryEntry (or null)


RETRIEVE (Fuzzy/Relevant):
User: "What's my hint?"
│
└─ MemoryStore.retrieveRelevant("hint", topK=3, byteBudget=512)
   │
   ├─ Tokenize query: {hint}
   ├─ Tokenize each entry topic: {password, hint}, {favorite, coffee}, ...
   ├─ Score by token overlap
   ├─ Return top 3 by score (sorted by createdAt descending)
   └─ Cap total bytes at 512
```

---

## Summary Diagram: From User Speech to Response

```
┌──────────────────────────────────────────────────────────────────┐
│ User speaks into glasses microphone                              │
└────────────────────┬─────────────────────────────────────────────┘
                     │
          ┌──────────▼─────────────┐
          │ MetaWearablesAudio    │
          │ Capture PCM @ 8kHz    │
          └──────────┬─────────────┘
                     │
          ┌──────────▼─────────────────────┐
          │ WhisperSpeechToText            │
          │ Transcribe audio → text        │
          └──────────┬─────────────────────┘
                     │
          ┌──────────▼──────────────────────────┐
          │ AiService.extract                   │
          │ Intent classification + parameters  │
          └──────────┬──────────────────────────┘
                     │
          ┌──────────▼──────────────────────────┐
          │ FeatureExecutor lookup              │
          ├──────────┬──────────────────────────┤
          │ Found?   │ NO                       │
          └──┬───────┘                          │
             │                                  │
    ┌────────▼──────────┐          ┌────────────▼────────────┐
    │ Execute handler   │          │ Legacy path:            │
    │ (e.g., remember) │          │ • Apply side effects    │
    │                  │          │ • Build template        │
    │ Return response   │          │ • Polish with LLM       │
    └────────┬──────────┘          │                        │
             │                     │ Return template         │
             │                     └────────────┬────────────┘
             │                                  │
             └──────────┬───────────────────────┘
                        │
             ┌──────────▼─────────────────────────┐
             │ FlutterTtsSpeech                   │
             │ Convert text → audio               │
             └──────────┬─────────────────────────┘
                        │
             ┌──────────▼─────────────────────────┐
             │ MetaWearablesAudio                 │
             │ Play audio through glasses speaker │
             └─────────────────────────────────────┘
```

---

## Getting Started with Modifications

### Adding a New Feature

**Example: "Set a reminder"**

1. **Add to AiManifests** (`lib/core/constants/manifests.dart`)
   ```dart
   {
     "featureId": "set_reminder_v1",
     "prompt": "Extract reminder text and time from: ...",
   }
   ```

2. **Create Executor** (new file, e.g., `lib/core/features/set_reminder_executor.dart`)
   ```dart
   class SetReminderExecutor implements FeatureExecutor {
     @override
     String get featureId => "set_reminder_v1";
     
     @override
     Future<String> execute(ExtractionResult result, {required String transcript}) async {
       final text = result.parameters['text'];
       final time = result.parameters['time'];
       
       // Your logic here
       
       return "Reminder set for $text at $time.";
     }
   }
   ```

3. **Register Executor** (`lib/core/features/feature_executor.dart`)
   ```dart
   static final Map<String, FeatureExecutor> _byId = {
     for (final e in <FeatureExecutor>[
       // ... existing executors
       SetReminderExecutor(),  // Add this
     ])
       e.featureId: e,
   };
   ```

4. **Done!** No changes to AiService, download layer, or main pipeline needed.

---

### Extending the Memory System

Currently uses in-memory Map. To add persistence:

1. Create `MemoryStoreDb` extending MemoryStore
2. Override `remember()`, `recall()`, `retrieveRelevant()` to use SQLite/Realm
3. Swap `MemoryStore.instance` → `MemoryStoreDb()` in relevant services

---

### Testing a Feature

Use `HomeScreen` (text interface) without glasses:

1. Type command: "Remember my parking spot is level 3"
2. Hit "Send"
3. See extraction result + response in ExtractionResultCard
4. Check MemoriesScreen to verify storage

Then test on actual glasses with `GlassesVoiceScreen`.

---

**End of Architecture Guide**

This document maps the entire application flow from hardware input to user-facing response. Each class and component is intentionally designed to be testable, swappable, and extensible. Happy hacking!
