import VibeWriteShared
import Vapor

extension WritingGatewayWriteEnvelope: @retroactive Content {}
extension WritingAIResponse: @retroactive Content {}
extension WritingGatewayResponse: @retroactive Content {}
