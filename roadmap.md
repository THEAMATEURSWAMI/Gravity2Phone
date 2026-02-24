# Antigravity Bridge: Roadmap

This roadmap outlines the path to a fully functional voice-controlled mobile development bridge.

## Phase 1: MVP - The Command & Control (Days 1-5)
- [ ] **Infrastructure**: Set up Tailscale mesh between Mobile and Dev Machine.
- [ ] **Remote Agent**: Create a Python script that listens on a port and executes `ls`, `git status`, etc.
- [ ] **Basic Client**: Simple Flutter app with a text input to send commands and a text area to show results.
- [ ] **Security**: Implement Token-based authentication for the Agent.

## Phase 2: The "Ding" System (Days 6-12)
- [ ] **Firebase Setup**: Register the app with Firebase and set up FCM.
- [ ] **Dispatcher**: Create a CLI utility on the Dev Machine (`ding "Message"`) that sends a push notification.
- [ ] **Actionable Notifications**: Update Flutter app to handle foreground/background notifications with "Approve/Reject" buttons.
- [ ] **Integration**: Hook `ding` into a sample build script.

## Phase 3: Voice Interface (Days 13-20)
- [ ] **STT Integration**: Add Speech-to-Text to the Flutter app.
- [ ] **Command Mapping**: Create a configuration file to map natural language to shell commands (e.g., "Check changes" -> `git status`).
- [ ] **UI/UX Polish**: Premium "Antigravity Universe" design – dark mode, neon accents, pulse animations on voice input.

## Phase 4: Full Autonomy (Future)
- [ ] **Log Streaming**: Real-time log tailing to the mobile device via WebSockets.
- [ ] **Environment Selector**: Support for multiple remote environments.
- [ ] **Voice Feedback**: Use TTS (Text-to-Speech) to have the app report "Build successful, ready for deployment."
