import Vapor

func configure(_ app: Application) throws {
    let deviceRegistry = InMemoryDeviceRegistry()
    let writeService = WriteService(deviceRegistry: deviceRegistry)
    try routes(app, deviceRegistry: deviceRegistry, writeService: writeService)
}
