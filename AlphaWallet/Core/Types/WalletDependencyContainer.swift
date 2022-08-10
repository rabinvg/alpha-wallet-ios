//
//  WalletDependencyContainer.swift
//  AlphaWallet
//
//  Created by Vladyslav Shepitko on 26.07.2022.
//

import Foundation

protocol WalletDependencyContainer {
    func destroy(for wallet: Wallet)
    func makeDependencies(for wallet: Wallet) -> WalletDependency
}

protocol WalletDependency {
    var store: RealmStore { get }
    var tokensDataStore: TokensDataStore { get }
    var transactionsDataStore: TransactionDataStore { get }
    var importToken: ImportToken { get }
    var tokensService: TokensService { get }
    var pipeline: TokensProcessingPipeline { get }
    var fetcher: WalletBalanceFetcher { get }
    var sessionsProvider: SessionsProvider { get }
}

class WalletComponentsFactory: WalletDependencyContainer {
    let analytics: AnalyticsServiceType
    let nftProvider: NFTProvider
    let assetDefinitionStore: AssetDefinitionStore
    let coinTickersFetcher: CoinTickersFetcher
    let config: Config

    private var walletDependencies: [Wallet: WalletDependency] = [:]

    struct Dependencies: WalletDependency {
        let store: RealmStore
        let tokensDataStore: TokensDataStore
        let transactionsDataStore: TransactionDataStore
        let importToken: ImportToken
        let tokensService: TokensService
        let pipeline: TokensProcessingPipeline
        let fetcher: WalletBalanceFetcher
        let sessionsProvider: SessionsProvider
        let eventsDataStore: NonActivityEventsDataStore
    }

    init(analytics: AnalyticsServiceType, nftProvider: NFTProvider, assetDefinitionStore: AssetDefinitionStore, coinTickersFetcher: CoinTickersFetcher, config: Config) {
        self.analytics = analytics
        self.nftProvider = nftProvider
        self.assetDefinitionStore = assetDefinitionStore
        self.coinTickersFetcher = coinTickersFetcher
        self.config = config
    }

    func makeDependencies(for wallet: Wallet) -> WalletDependency {
        if let dep = walletDependencies[wallet] { return dep }

        let store: RealmStore = .storage(for: wallet)
        let tokensDataStore: TokensDataStore = MultipleChainsTokensDataStore(store: store, servers: config.enabledServers)
        let eventsDataStore: NonActivityEventsDataStore = NonActivityMultiChainEventsDataStore(store: store)
        let transactionsDataStore = TransactionDataStore(store: store)

        let sessionsProvider: SessionsProvider = .init(config: config, analytics: analytics)

        let importToken = ImportToken(sessionProvider: sessionsProvider, wallet: wallet, tokensDataStore: tokensDataStore, assetDefinitionStore: assetDefinitionStore, analytics: analytics)

        let tokensService: TokensService = AlphaWalletTokensService(sessionsProvider: sessionsProvider, tokensDataStore: tokensDataStore, analytics: analytics, importToken: importToken, transactionsStorage: transactionsDataStore, nftProvider: nftProvider, assetDefinitionStore: assetDefinitionStore)
        let pipeline: TokensProcessingPipeline = WalletDataProcessingPipeline(wallet: wallet, tokensService: tokensService, coinTickersFetcher: coinTickersFetcher, assetDefinitionStore: assetDefinitionStore, eventsDataStore: eventsDataStore)

        let fetcher = WalletBalanceFetcher(wallet: wallet, service: pipeline)

        let dependency: WalletDependency = Dependencies(store: store, tokensDataStore: tokensDataStore, transactionsDataStore: transactionsDataStore, importToken: importToken, tokensService: tokensService, pipeline: pipeline, fetcher: fetcher, sessionsProvider: sessionsProvider, eventsDataStore: eventsDataStore)

        walletDependencies[wallet] = dependency

        return dependency
    }

    func destroy(for wallet: Wallet) {
        walletDependencies[wallet] = nil
    }
}