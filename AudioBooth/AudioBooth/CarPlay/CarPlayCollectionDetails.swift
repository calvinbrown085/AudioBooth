import API
@preconcurrency import CarPlay
import Foundation
import Nuke

final class CarPlayCollectionDetails {
  private let interfaceController: CPInterfaceController
  private weak var nowPlaying: CarPlayNowPlaying?
  private let name: String
  private let items: [QueueItem]
  private var loadingTask: Task<Void, Never>?

  let template: CPListTemplate

  init(
    interfaceController: CPInterfaceController,
    nowPlaying: CarPlayNowPlaying,
    name: String,
    items: [QueueItem]
  ) {
    self.interfaceController = interfaceController
    self.nowPlaying = nowPlaying
    self.name = name
    self.items = items

    template = CPListTemplate(title: name, sections: [])
    buildSections()
  }

  private func buildSections() {
    guard !items.isEmpty else {
      template.emptyViewTitleVariants = [String(localized: "No Items")]
      return
    }

    let playAllItem = CPListItem(
      text: String(localized: "Play All"),
      detailText: "\(items.count) item\(items.count == 1 ? "" : "s")"
    )
    playAllItem.setImage(UIImage(systemName: "play.fill"))
    playAllItem.handler = { [weak self] _, completion in
      self?.onPlayAll()
      completion()
    }

    let trackItems = items.enumerated().map { index, queueItem in
      createListItem(for: queueItem, index: index)
    }

    let playAllSection = CPListSection(items: [playAllItem])
    let tracksSection = CPListSection(items: trackItems)
    template.updateSections([playAllSection, tracksSection])
  }

  private func createListItem(for queueItem: QueueItem, index: Int) -> CPListItem {
    let item = CPListItem(
      text: queueItem.title,
      detailText: queueItem.details
    )

    item.isPlaying = queueItem.bookID == PlayerManager.shared.current?.id

    if let coverURL = queueItem.coverURL {
      Task {
        if let image = await loadImage(from: coverURL) {
          item.setImage(image)
        }
      }
    }

    item.handler = { [weak self] _, completion in
      self?.onItemSelected(from: index)
      completion()
    }

    return item
  }

  private func onPlayAll() {
    loadingTask?.cancel()
    loadingTask = Task {
      PlayerManager.shared.playAll(items)
      await waitForPlayerReady()
      try? await Task.sleep(for: .milliseconds(500))
      nowPlaying?.showNowPlaying()
      loadingTask = nil
    }
  }

  private func onItemSelected(from index: Int) {
    loadingTask?.cancel()
    loadingTask = Task {
      let remaining = Array(items[index...])
      PlayerManager.shared.playAll(remaining)
      await waitForPlayerReady()
      try? await Task.sleep(for: .milliseconds(500))
      nowPlaying?.showNowPlaying()
      loadingTask = nil
    }
  }

  private func waitForPlayerReady() async {
    guard PlayerManager.shared.current?.isLoading == true else { return }

    await withCheckedContinuation { continuation in
      observePlayerLoading(continuation: continuation)
    }
  }

  private func observePlayerLoading(continuation: CheckedContinuation<Void, Never>) {
    withObservationTracking {
      _ = PlayerManager.shared.current?.isLoading
    } onChange: {
      RunLoop.main.perform {
        if PlayerManager.shared.current?.isLoading == false {
          continuation.resume()
        } else {
          self.observePlayerLoading(continuation: continuation)
        }
      }
    }
  }

  private func loadImage(from url: URL) async -> UIImage? {
    let request = ImageRequest(url: url)
    return try? await ImagePipeline.shared.image(for: request)
  }
}
