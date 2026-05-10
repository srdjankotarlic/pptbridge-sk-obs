#pragma once

#include <cstdint>

namespace pptbridge {

enum class OscAction {
  Next,
  Previous,
  First,
  Last,
  Black,
  Reload,
};

using OscActionCallback = void (*)(OscAction action);

bool StartOscServer(uint16_t port, OscActionCallback callback);
void StopOscServer();
bool OscServerRunning();

}  // namespace pptbridge
