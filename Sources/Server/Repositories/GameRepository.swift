import Foundation
import GeoJSON
import MongoKitten

struct GameRepository {
    
    func add(_ game: Game) throws {
        guard game.id == nil else {
            try logAndThrow(ServerError.persistedEntity)
        }
        guard let newID = try collection(.games).insert(game.toBSON()) as? ObjectId else {
            try logAndThrow(BSONError.missingField(name: "_id"))
        }
        game.id = newID.hexString
    }
    
    func game(withID id: String, withDistanceMeasuredFrom location: Location? = nil) throws -> Game? {
        if let location = location {
            return try games(matching: ["_id": ObjectId(id)],
                             withDistanceMeasuredFrom: location,
                             sortedBy: ["creationDate": .descending],
                             startingFrom: 0, limitedTo: 1).first
        } else {
            return try collection(.games).findOne(["_id": ObjectId(id)]).map { try Game(bson: $0) }
        }
    }
    
    func newestGames(withDistanceMeasuredFrom location: Location, startingFrom start: Int = 0, limitedTo limit: Int, excludingGamesHostedBy host: User) throws -> [Game] {
        return try games(matching: ["host": ["$ne": host.id], "deadline": ["$gt": Date()], "cancelled": false],
                         withDistanceMeasuredFrom: location,
                         sortedBy: ["creationDate": .descending],
                         startingFrom: start, limitedTo: limit)
    }
    
    func upcomingGames(withDistanceMeasuredFrom location: Location, startingFrom start: Int = 0, limitedTo limit: Int, excludingGamesHostedBy host: User) throws -> [Game] {
        return try games(matching: ["host": ["$ne": host.id], "deadline": ["$gt": Date()], "cancelled": false],
                         withDistanceMeasuredFrom: location,
                         sortedBy: ["date": .ascending, "location.distance": .ascending],
                         startingFrom: start, limitedTo: limit)
    }
    
    func gamesNearMe(withDistanceMeasuredFrom location: Location, startingFrom start: Int = 0, limitedTo limit: Int, excludingGamesHostedBy host: User) throws -> [Game] {
        return try games(matching: ["host": ["$ne": host.id], "deadline": ["$gt": Date()], "cancelled": false],
                         withDistanceMeasuredFrom: location,
                         sortedBy: ["location.distance": .ascending, "date": .ascending],
                         startingFrom: start, limitedTo: limit)
    }
    
    func games(hostedBy host: User) throws -> [Game] {
        return try collection(.games).find(["host": host.id, "date": ["$gt": Date()], "cancelled": false], sortedBy: ["date": .ascending]).map { try Game(bson: $0) }
    }
    
    func games(joinedBy player: User, withDistanceMeasuredFrom location: Location) throws -> [Game] {
        let gameIDs = try collection(.requests)
            .find(["player": player.id, "approved": true, "cancelled": false], projecting: ["_id": false, "game": true])
            .flatMap { String($0["game"]) }
            .map { try ObjectId($0) }
        return try games(matching: ["_id": ["$in": gameIDs], "date": ["$gt": Date()], "cancelled": false],
                         withDistanceMeasuredFrom: location,
                         sortedBy: ["date": .ascending],
                         startingFrom: 0, limitedTo: gameIDs.count)
    }
    
    func availableGamesCount(excludingGamesHostedBy host: User) throws -> Int {
        return try collection(.games).count(["host": ["$ne": host.id], "deadline": ["$gt": Date()], "cancelled": false])
    }
    
    /*
     Looks up games using a geoNear query and adds a `location.distance` property.
     */
    private func games(matching query: Query,
                       withDistanceMeasuredFrom location: Location,
                       sortedBy sort: Sort,
                       startingFrom start: Int,
                       limitedTo limit: Int) throws -> [Game] {
        let results = try collection(.games).aggregate([
            .geoNear(options: GeoNearOptions(
                near: Point(coordinate: Position(first: location.longitude, second: location.latitude)),
                spherical: true,
                distanceField: "location.distance",
                limit: try collection(.games).count(),
                query: query
            )),
            .sort(sort)
        ]).dropFirst(start).prefix(limit)
        return try results.map { try Game(bson: $0) }
    }
    
    func cancel(_ game: Game) throws {
        guard let id = game.id else {
            try logAndThrow(ServerError.unpersistedEntity)
        }
        game.cancelled = true
        try collection(.games).update(["_id": try ObjectId(id)], to: ["$set": ["cancelled": true]])
    }
}
