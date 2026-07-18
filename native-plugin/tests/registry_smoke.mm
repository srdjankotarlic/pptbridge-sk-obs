#include "../src/pptbridge_registry.hpp"

#include <cstdio>
#include <memory>
#include <string>

using pptbridge::RegisteredSourceKind;
using pptbridge::Registry;

int main()
{
  @autoreleasepool {
    auto &registry = Registry::Instance();
    if (registry.Acquire("")) {
      std::fprintf(stderr, "empty path unexpectedly created a document\n");
      return 1;
    }

    const std::string deck_a = "/tmp/pptbridge-registry-a.pptx";
    const std::string deck_b = "/tmp/pptbridge-registry-b.pdf";
    auto first_a = registry.Acquire(deck_a);
    auto second_a = registry.Acquire(deck_a);
    auto first_b = registry.Acquire(deck_b);
    if (!first_a || !first_b || first_a != second_a || first_a == first_b) {
      std::fprintf(stderr, "document sharing or deck isolation failed\n");
      return 1;
    }

    int slide_a_token = 0;
    int presenter_a_token = 0;
    int slide_b_token = 0;
    registry.AttachSource(&slide_a_token, deck_a, RegisteredSourceKind::Slide);
    registry.AttachSource(&presenter_a_token, deck_a, RegisteredSourceKind::Presenter);
    registry.AttachSource(&slide_b_token, deck_b, RegisteredSourceKind::Slide);
    if (registry.CountSources(deck_a, RegisteredSourceKind::Slide) != 1 ||
        registry.CountSources(deck_a, RegisteredSourceKind::Presenter) != 1 ||
        registry.CountSources(deck_b, RegisteredSourceKind::Slide) != 1 ||
        registry.CountSources(deck_b, RegisteredSourceKind::Presenter) != 0) {
      std::fprintf(stderr, "registered source counts are incorrect\n");
      return 1;
    }

    const auto deck_a_slides = registry.SourceTokens(deck_a, RegisteredSourceKind::Slide);
    const auto deck_a_presenters = registry.SourceTokens(deck_a, RegisteredSourceKind::Presenter);
    const auto deck_b_slides = registry.SourceTokens(deck_b, RegisteredSourceKind::Slide);
    if (deck_a_slides.size() != 1 || deck_a_slides.front() != &slide_a_token ||
        deck_a_presenters.size() != 1 || deck_a_presenters.front() != &presenter_a_token ||
        deck_b_slides.size() != 1 || deck_b_slides.front() != &slide_b_token ||
        !registry.SourceTokens("", RegisteredSourceKind::Slide).empty()) {
      std::fprintf(stderr, "registered source token lookup is incorrect\n");
      return 1;
    }

    registry.SetActive(first_b);
    if (registry.Active() != first_b) {
      std::fprintf(stderr, "active deck selection failed\n");
      return 1;
    }

    registry.AttachSource(&slide_b_token, "", RegisteredSourceKind::Slide);
    registry.DetachSource(&slide_a_token);
    registry.DetachSource(&presenter_a_token);
    if (registry.CountSources(deck_a, RegisteredSourceKind::Slide) != 0 ||
        registry.CountSources(deck_a, RegisteredSourceKind::Presenter) != 0 ||
        registry.CountSources(deck_b, RegisteredSourceKind::Slide) != 0) {
      std::fprintf(stderr, "registered source cleanup failed\n");
      return 1;
    }
    if (!registry.SourceTokens(deck_a, RegisteredSourceKind::Slide).empty() ||
        !registry.SourceTokens(deck_a, RegisteredSourceKind::Presenter).empty() ||
        !registry.SourceTokens(deck_b, RegisteredSourceKind::Slide).empty()) {
      std::fprintf(stderr, "registered source token cleanup failed\n");
      return 1;
    }

    registry.SetActive(nullptr);
    if (registry.Active()) {
      std::fprintf(stderr, "active deck cleanup failed\n");
      return 1;
    }

    std::printf("registry smoke passed\n");
    return 0;
  }
}
