#pragma once

#include <cstdint>
#include <string>

#include "presentation_document.hpp"

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
bool SendOscStatusFeedback(const std::string &host, uint16_t port, const PresentationStatus &status);

}  // namespace pptbridge
