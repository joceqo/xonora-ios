import CarPlay
import UIKit

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        
        let libraryTemplate = CPListTemplate(title: "Library", sections: [
            CPListSection(items: [
                CPListItem(text: "Albums", detailText: "Browse your music library", image: UIImage(systemName: "rectangle.stack.fill")),
                CPListItem(text: "Playlists", detailText: "Your custom collections", image: UIImage(systemName: "music.note.list")),
                CPListItem(text: "Artists", detailText: "Browse by artist", image: UIImage(systemName: "person.2.fill"))
            ])
        ])
        
        libraryTemplate.delegate = self
        interfaceController.setRootTemplate(libraryTemplate, animated: true, completion: nil)
    }
}

extension CarPlaySceneDelegate: CPListTemplateDelegate {
    func listTemplate(_ listTemplate: CPListTemplate, didSelect item: CPListItem, completionHandler: @escaping () -> Void) {
        guard let interfaceController = interfaceController else {
            completionHandler()
            return
        }
        
        if let album = item.userInfo as? Album {
            showTracks(for: album, interfaceController: interfaceController, completionHandler: completionHandler)
        } else if let playlist = item.userInfo as? Playlist {
            showTracks(for: playlist, interfaceController: interfaceController, completionHandler: completionHandler)
        } else if let track = item.userInfo as? Track {
            playTrack(track, completionHandler: completionHandler)
        } else if item.text == "Albums" {
            showAlbums(interfaceController: interfaceController, completionHandler: completionHandler)
        } else if item.text == "Playlists" {
            showPlaylists(interfaceController: interfaceController, completionHandler: completionHandler)
        } else if item.text == "Artists" {
            showArtists(interfaceController: interfaceController, completionHandler: completionHandler)
        } else {
            completionHandler()
        }
    }
    
    private func showAlbums(interfaceController: CPInterfaceController, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            let albums = LibraryViewModel.shared.albums
            let listItems = albums.map { album in
                let listItem = CPListItem(text: album.name, detailText: album.artistNames)
                listItem.userInfo = album
                return listItem
            }
            
            let template = CPListTemplate(title: "Albums", sections: [CPListSection(items: listItems)])
            template.delegate = self
            interfaceController.pushTemplate(template, animated: true, completion: nil)
            completionHandler()
        }
    }
    
    private func showPlaylists(interfaceController: CPInterfaceController, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            let playlists = LibraryViewModel.shared.playlists
            let listItems = playlists.map { playlist in
                let listItem = CPListItem(text: playlist.name, detailText: "Playlist")
                listItem.userInfo = playlist
                return listItem
            }
            
            let template = CPListTemplate(title: "Playlists", sections: [CPListSection(items: listItems)])
            template.delegate = self
            interfaceController.pushTemplate(template, animated: true, completion: nil)
            completionHandler()
        }
    }
    
    private func showArtists(interfaceController: CPInterfaceController, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            let artists = LibraryViewModel.shared.artists
            let listItems = artists.map { artist in
                let listItem = CPListItem(text: artist.name, detailText: nil)
                listItem.userInfo = artist
                return listItem
            }
            
            let template = CPListTemplate(title: "Artists", sections: [CPListSection(items: listItems)])
            template.delegate = self
            interfaceController.pushTemplate(template, animated: true, completion: nil)
            completionHandler()
        }
    }

    private func showTracks(for album: Album, interfaceController: CPInterfaceController, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            do {
                let tracks = try await LibraryViewModel.shared.loadAlbumTracks(album: album)
                let listItems = tracks.map { track in
                    let listItem = CPListItem(text: track.name, detailText: track.artistNames)
                    listItem.userInfo = track
                    return listItem
                }
                
                let template = CPListTemplate(title: album.name, sections: [CPListSection(items: listItems)])
                template.delegate = self
                interfaceController.pushTemplate(template, animated: true, completion: nil)
            } catch {
                print("Failed to load CarPlay tracks for album: \(error)")
            }
            completionHandler()
        }
    }

    private func showTracks(for playlist: Playlist, interfaceController: CPInterfaceController, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            do {
                let tracks = try await LibraryViewModel.shared.loadPlaylistTracks(playlist: playlist)
                let listItems = tracks.map { track in
                    let listItem = CPListItem(text: track.name, detailText: track.artistNames)
                    listItem.userInfo = track
                    return listItem
                }
                
                let template = CPListTemplate(title: playlist.name, sections: [CPListSection(items: listItems)])
                template.delegate = self
                interfaceController.pushTemplate(template, animated: true, completion: nil)
            } catch {
                print("Failed to load CarPlay tracks for playlist: \(error)")
            }
            completionHandler()
        }
    }

    private func playTrack(_ track: Track, completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            PlayerManager.shared.playTrack(track)
            completionHandler()
        }
    }
}
