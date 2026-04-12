import Vapor

func configure(
    _ app: Application,
    quotaLedger: InMemoryQuotaLedger = InMemoryQuotaLedger()
) throws {
    let deviceRegistry = InMemoryDeviceRegistry()
    let writeService = WriteService(
        deviceRegistry: deviceRegistry,
        quotaLedger: quotaLedger
    )
    try routes(app, deviceRegistry: deviceRegistry, writeService: writeService)
}
