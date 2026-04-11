import Vapor

func configure(_ app: Application) throws {
    let deviceRegistry = InMemoryDeviceRegistry()
    try routes(app, deviceRegistry: deviceRegistry)
}
