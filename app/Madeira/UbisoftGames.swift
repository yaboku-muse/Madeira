// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// Ubisoft game library: owned games via Ubisoft's entitlement API.
//
// Uses the session ticket from UbisoftAuth to query the player's
// entitlements, then resolves each to a UbisoftDockGame (numeric game ID
// for the uplay://launch/ URL). Results are cached in memory for the
// session; the authoritative install state lives in the Connect client.
import Foundation

struct UbisoftGame: Identifiable {
    var id: String          // Ubisoft numeric game ID, e.g. "420"
    var name: String
    var installID: String?  // for uplay://install/ links

    var dockGame: UbisoftDockGame {
        UbisoftDockGame(id: id, name: name)
    }
}

final class UbisoftGames {
    static let shared = UbisoftGames()
    private init() {}

    private static let entitlementsURL = URL(
        string: "https://api-ubiservices.ubi.com/v1/profiles/me/global/ubiconnect/entitlement/api/entitlements")!
    private static let graphqlURL = URL(
        string: "https://public-ubiservices.ubi.com/v1/profiles/me/uplay/graphql")!
    private static let appID = "314d4fef-e568-454a-ae06-43e3bece12a6"

    private var cache: [UbisoftGame]?

    func clearCache() { cache = nil }

    /// Owned games, via the GraphQL GetOwnedGames operation.
    func ownedGames() async throws -> [UbisoftGame] {
        if let cache { return cache }
        let session = try await UbisoftAuth.shared.validSession()

        // GetOwnedGames GraphQL query (shape from the GOG Galaxy plugin).
        let query = """
        query GetOwnedGames($limit: Int) {
          viewer { ownedGames(limit: $limit) {
            nodes { id name spaceId }
          } }
        }
        """
        var req = URLRequest(url: Self.graphqlURL)
        req.httpMethod = "POST"
        req.setValue("Ubi_v1 t=\(session.ticket)", forHTTPHeaderField: "Authorization")
        req.setValue(Self.appID, forHTTPHeaderField: "Ubi-AppId")
        req.setValue(session.sessionID, forHTTPHeaderField: "Ubi-SessionId")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "operationName": "GetOwnedGames",
            "query": query,
            "variables": ["limit": 200],
        ])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let viewer = dataObj["viewer"] as? [String: Any],
              let owned = viewer["ownedGames"] as? [String: Any],
              let nodes = owned["nodes"] as? [[String: Any]] else {
            throw UbisoftAuthError.loginFailed("could not load the Ubisoft library")
        }
        // Node IDs are like "UplayGame:12345" or carry a spaceId; the numeric
        // game ID for uplay://launch/ is extracted from the id suffix.
        var games: [UbisoftGame] = []
        for node in nodes {
            guard let rawID = node["id"] as? String,
                  let name = node["name"] as? String else { continue }
            let numeric = rawID.split(separator: ":").last.map(String.init) ?? rawID
            guard numeric.allSatisfy({ $0.isNumber }) else { continue }
            games.append(UbisoftGame(id: numeric, name: name))
        }
        games.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cache = games
        return games
    }
}
