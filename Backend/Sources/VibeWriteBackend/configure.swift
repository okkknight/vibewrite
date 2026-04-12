import Vapor

func configure(
    _ app: Application,
    quotaLedger: InMemoryQuotaLedger? = nil,
    requestLogStore: InMemoryRequestLogStore = InMemoryRequestLogStore(),
    clock: any VibeWriteClock = SystemVibeWriteClock()
) throws {
    let deviceRegistry = InMemoryDeviceRegistry()
    let resolvedQuotaLedger = quotaLedger ?? InMemoryQuotaLedger(clock: clock)
    let writeService = WriteService(
        deviceRegistry: deviceRegistry,
        quotaLedger: resolvedQuotaLedger,
        requestLogStore: requestLogStore,
        clock: clock
    )
    try routes(app, deviceRegistry: deviceRegistry, writeService: writeService)
}
