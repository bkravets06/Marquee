import Foundation
import SwiftData
import MarqueeKit

// MARK: - PreviewData

/// In-memory sample data for `#Preview` blocks and tests.
enum PreviewData {

    // MARK: Container

    /// A pre-populated in-memory container. Created once per process.
    @MainActor
    static let container: ModelContainer = {
        let schema = Schema([MediaItem.self])
        let configuration = ModelConfiguration("MarqueePreview", schema: schema, isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            _ = sampleItems(context: container.mainContext)
            return container
        } catch {
            fatalError("PreviewData could not create an in-memory container: \(error)")
        }
    }()

    /// Every item in `container`, oldest first.
    @MainActor
    static var items: [MediaItem] {
        let descriptor = FetchDescriptor<MediaItem>(sortBy: [SortDescriptor(\MediaItem.addedAt)])
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }

    /// A TMDB show that is being watched and has an upcoming episode.
    @MainActor
    static var sampleShow: MediaItem {
        items.first { $0.isShow && !$0.isCustom && $0.nextEpisodeAirDate != nil } ?? sampleItems()[0]
    }

    /// A TMDB movie in the library.
    @MainActor
    static var sampleMovie: MediaItem {
        items.first { $0.isMovie && !$0.isCustom } ?? sampleItems()[2]
    }

    /// A custom show with a weekly release schedule.
    @MainActor
    static var sampleCustomShow: MediaItem {
        items.first { $0.isCustom } ?? sampleItems()[5]
    }

    // MARK: Items

    /// Builds the sample items and inserts them into `context`.
    @MainActor
    @discardableResult
    static func sampleItems(context: ModelContext) -> [MediaItem] {
        let items = sampleItems()
        for item in items {
            context.insert(item)
        }
        try? context.save()
        return items
    }

    /// Builds the sample items without inserting them anywhere.
    static func sampleItems() -> [MediaItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let inTwoDays = calendar.date(byAdding: .day, value: 2, to: today) ?? today

        let severance = MediaItem(
            kind: .show,
            status: .watching,
            title: "Severance",
            tmdbID: 95396,
            overview: "Mark leads a team of office workers whose memories have been surgically divided between their work and personal lives. When a mysterious colleague appears outside of work, it begins a journey to discover the truth about their jobs.",
            tagline: "Who are you at work?",
            posterPath: "/pPHpeI2X1qEd1CS1SeyrdhZ4qnT.jpg",
            backdropPath: "/vcPGPBpGyGGveNJgGs3J4qWKvE1.jpg",
            releaseDate: date(2022, 2, 18),
            genres: ["Drama", "Mystery", "Sci-Fi & Fantasy"],
            runtimeMinutes: 50,
            voteAverage: 8.4,
            showStatus: "Returning Series",
            totalEpisodes: 19,
            notificationsEnabled: true
        )
        severance.seasons = [
            SeasonInfo(number: 1, name: "Season 1", episodeCount: 9, airDate: CivilDate(year: 2022, month: 2, day: 18)),
            SeasonInfo(number: 2, name: "Season 2", episodeCount: 10, airDate: CivilDate(year: 2025, month: 1, day: 17))
        ]
        severance.progress = EpisodePointer(season: 2, episode: 4)
        severance.nextEpisodeAirDate = inTwoDays
        severance.nextEpisodeSeason = 2
        severance.nextEpisodeNumber = 5
        severance.nextEpisodeName = "Trojan's Horse"
        severance.lastWatchedAt = calendar.date(byAdding: .day, value: -3, to: today)
        severance.lastRefreshedAt = calendar.date(byAdding: .hour, value: -2, to: .now)

        let slowHorses = MediaItem(
            kind: .show,
            status: .watching,
            title: "Slow Horses",
            tmdbID: 95480,
            overview: "Follow a dysfunctional team of MI5 agents and their obnoxious boss, the notorious Jackson Lamb, as they navigate the espionage world's smoke and mirrors to defend England from sinister forces.",
            tagline: "Even losers have their day.",
            posterPath: "/dnpatlJrEPiDSn5fzgzvxtiSnMo.jpg",
            backdropPath: "/2Nx6UL8Bd0I7XPv8yX45uoWc0pg.jpg",
            releaseDate: date(2022, 4, 1),
            genres: ["Drama", "Crime"],
            runtimeMinutes: 45,
            voteAverage: 7.9,
            showStatus: "Returning Series",
            totalEpisodes: 24,
            notificationsEnabled: true
        )
        slowHorses.seasons = [
            SeasonInfo(number: 1, name: "Season 1", episodeCount: 6),
            SeasonInfo(number: 2, name: "Season 2", episodeCount: 6),
            SeasonInfo(number: 3, name: "Season 3", episodeCount: 6),
            SeasonInfo(number: 4, name: "Season 4", episodeCount: 6)
        ]
        slowHorses.progress = EpisodePointer(season: 3, episode: 2)
        slowHorses.lastWatchedAt = calendar.date(byAdding: .day, value: -1, to: today)
        slowHorses.lastRefreshedAt = calendar.date(byAdding: .hour, value: -5, to: .now)

        let dune = MediaItem(
            kind: .movie,
            status: .watching,
            title: "Dune: Part Two",
            tmdbID: 693134,
            overview: "Follow the mythic journey of Paul Atreides as he unites with Chani and the Fremen while on a path of revenge against the conspirators who destroyed his family.",
            tagline: "Long live the fighters.",
            posterPath: "/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg",
            backdropPath: "/xOMo8BRK7PfcJv9JCnx7s5hj0PX.jpg",
            releaseDate: date(2024, 3, 1),
            genres: ["Science Fiction", "Adventure"],
            runtimeMinutes: 167,
            voteAverage: 8.2
        )

        let theBear = MediaItem(
            kind: .show,
            status: .watchlist,
            title: "The Bear",
            tmdbID: 136315,
            overview: "Carmy, a young fine-dining chef, comes home to Chicago to run his family sandwich shop.",
            posterPath: "/sHFlbKS3WLqMnp9t2ghADIJFnuQ.jpg",
            backdropPath: "/8nP1w6YpOIM0uUmd9YkT1VYv6Gj.jpg",
            releaseDate: date(2022, 6, 23),
            genres: ["Comedy", "Drama"],
            runtimeMinutes: 30,
            voteAverage: 8.3,
            showStatus: "Returning Series",
            totalEpisodes: 28
        )
        theBear.seasons = [
            SeasonInfo(number: 1, name: "Season 1", episodeCount: 8),
            SeasonInfo(number: 2, name: "Season 2", episodeCount: 10),
            SeasonInfo(number: 3, name: "Season 3", episodeCount: 10)
        ]

        let pastLives = MediaItem(
            kind: .movie,
            status: .watched,
            title: "Past Lives",
            tmdbID: 666277,
            overview: "Nora and Hae Sung, two childhood friends, are reunited in New York for one fateful week as they confront notions of destiny, love, and the choices that make a life.",
            posterPath: "/k3waqVXSnvCZWfJYNtdamTgTtTA.jpg",
            backdropPath: "/kZ0lbOG5OtVXRHhVy0I3CdODYiT.jpg",
            releaseDate: date(2023, 6, 2),
            genres: ["Drama", "Romance"],
            runtimeMinutes: 106,
            voteAverage: 7.8
        )
        pastLives.finishedAt = calendar.date(byAdding: .day, value: -12, to: today)
        pastLives.lastWatchedAt = pastLives.finishedAt

        let customShow = MediaItem(
            kind: .show,
            status: .watching,
            title: "Studio Rewatch Club",
            overview: "A weekly rewatch with friends. One episode every Tuesday night.",
            totalEpisodes: 12,
            isCustom: true,
            linkURL: URL(string: "https://example.com/rewatch"),
            notes: "Bring snacks. We rotate hosts every month.",
            notificationsEnabled: true
        )
        customShow.progress = EpisodePointer(season: 1, episode: 3)
        customShow.releaseSchedule = ReleaseSchedule(weekday: 3, hour: 20, minute: 0)
        customShow.lastWatchedAt = calendar.date(byAdding: .day, value: -6, to: today)

        return [severance, slowHorses, dune, theBear, pastLives, customShow]
    }

    // MARK: Catalog samples

    /// A TMDB search / trending row.
    static let sampleSummary = MediaSummary(
        id: 95396,
        kind: .show,
        title: "Severance",
        overview: "Mark leads a team of office workers whose memories have been surgically divided between their work and personal lives.",
        posterPath: "/pPHpeI2X1qEd1CS1SeyrdhZ4qnT.jpg",
        backdropPath: "/vcPGPBpGyGGveNJgGs3J4qWKvE1.jpg",
        releaseDate: CivilDate(year: 2022, month: 2, day: 18),
        voteAverage: 8.4,
        voteCount: 2143,
        popularity: 412.7,
        genreIDs: [18, 9648, 10765],
        originalLanguage: "en"
    )

    /// A TMDB movie row.
    static let sampleMovieSummary = MediaSummary(
        id: 693134,
        kind: .movie,
        title: "Dune: Part Two",
        overview: "Follow the mythic journey of Paul Atreides as he unites with Chani and the Fremen.",
        posterPath: "/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg",
        backdropPath: "/xOMo8BRK7PfcJv9JCnx7s5hj0PX.jpg",
        releaseDate: CivilDate(year: 2024, month: 3, day: 1),
        voteAverage: 8.2,
        voteCount: 5320,
        popularity: 388.1,
        genreIDs: [878, 12],
        originalLanguage: "en"
    )

    /// A handful of rows for carousels and grids.
    static let sampleSummaries: [MediaSummary] = [
        sampleSummary,
        sampleMovieSummary,
        MediaSummary(
            id: 95480,
            kind: .show,
            title: "Slow Horses",
            overview: "Follow a dysfunctional team of MI5 agents and their obnoxious boss, the notorious Jackson Lamb.",
            posterPath: "/dnpatlJrEPiDSn5fzgzvxtiSnMo.jpg",
            backdropPath: "/2Nx6UL8Bd0I7XPv8yX45uoWc0pg.jpg",
            releaseDate: CivilDate(year: 2022, month: 4, day: 1),
            voteAverage: 7.9,
            voteCount: 980,
            popularity: 210.4,
            genreIDs: [18, 80],
            originalLanguage: "en"
        ),
        MediaSummary(
            id: 136315,
            kind: .show,
            title: "The Bear",
            overview: "Carmy, a young fine-dining chef, comes home to Chicago to run his family sandwich shop.",
            posterPath: "/sHFlbKS3WLqMnp9t2ghADIJFnuQ.jpg",
            backdropPath: "/8nP1w6YpOIM0uUmd9YkT1VYv6Gj.jpg",
            releaseDate: CivilDate(year: 2022, month: 6, day: 23),
            voteAverage: 8.3,
            voteCount: 1500,
            popularity: 260.0,
            genreIDs: [35, 18],
            originalLanguage: "en"
        ),
        MediaSummary(
            id: 666277,
            kind: .movie,
            title: "Past Lives",
            overview: "Nora and Hae Sung, two childhood friends, are reunited in New York for one fateful week.",
            posterPath: "/k3waqVXSnvCZWfJYNtdamTgTtTA.jpg",
            backdropPath: "/kZ0lbOG5OtVXRHhVy0I3CdODYiT.jpg",
            releaseDate: CivilDate(year: 2023, month: 6, day: 2),
            voteAverage: 7.8,
            voteCount: 2100,
            popularity: 95.3,
            genreIDs: [18, 10749],
            originalLanguage: "en"
        )
    ]

    /// Full TMDB show details, including a next episode two days out.
    static let sampleShowDetails: TVShowDetails = {
        let today = CivilDate.today()
        let calendar = Calendar.current
        let inTwoDays = calendar.date(byAdding: .day, value: 2, to: .now).map { CivilDate($0) } ?? today
        return TVShowDetails(
            id: 95396,
            name: "Severance",
            overview: "Mark leads a team of office workers whose memories have been surgically divided between their work and personal lives. When a mysterious colleague appears outside of work, it begins a journey to discover the truth about their jobs.",
            tagline: "Who are you at work?",
            posterPath: "/pPHpeI2X1qEd1CS1SeyrdhZ4qnT.jpg",
            backdropPath: "/vcPGPBpGyGGveNJgGs3J4qWKvE1.jpg",
            firstAirDate: CivilDate(year: 2022, month: 2, day: 18),
            lastAirDate: CivilDate(year: 2025, month: 2, day: 14),
            genres: [
                Genre(id: 18, name: "Drama"),
                Genre(id: 9648, name: "Mystery"),
                Genre(id: 10765, name: "Sci-Fi & Fantasy")
            ],
            status: "Returning Series",
            type: "Scripted",
            numberOfSeasons: 2,
            numberOfEpisodes: 19,
            episodeRunTime: [50],
            seasons: [
                TVSeasonSummary(
                    id: 300001,
                    seasonNumber: 0,
                    name: "Specials",
                    overview: "",
                    episodeCount: 2,
                    airDate: nil,
                    posterPath: nil
                ),
                TVSeasonSummary(
                    id: 300002,
                    seasonNumber: 1,
                    name: "Season 1",
                    overview: "The team begins to question the nature of their work.",
                    episodeCount: 9,
                    airDate: CivilDate(year: 2022, month: 2, day: 18),
                    posterPath: "/pPHpeI2X1qEd1CS1SeyrdhZ4qnT.jpg"
                ),
                TVSeasonSummary(
                    id: 300003,
                    seasonNumber: 2,
                    name: "Season 2",
                    overview: "Mark and his friends learn the dire consequences of trifling with the severance barrier.",
                    episodeCount: 10,
                    airDate: CivilDate(year: 2025, month: 1, day: 17),
                    posterPath: nil
                )
            ],
            nextEpisodeToAir: EpisodeSummary(
                id: 400005,
                name: "Trojan's Horse",
                overview: "The team mourns a loss and makes a startling discovery.",
                seasonNumber: 2,
                episodeNumber: 5,
                airDate: inTwoDays,
                stillPath: nil,
                runtime: 48,
                voteAverage: 8.1
            ),
            lastEpisodeToAir: EpisodeSummary(
                id: 400004,
                name: "Woe's Hollow",
                overview: "The team goes on a mysterious retreat.",
                seasonNumber: 2,
                episodeNumber: 4,
                airDate: CivilDate(year: 2025, month: 2, day: 7),
                stillPath: nil,
                runtime: 51,
                voteAverage: 8.6
            ),
            networks: [Network(id: 2552, name: "Apple TV+", logoPath: "/4KAy34EHvRM25Ih8wb82AuGU7zJ.png")],
            voteAverage: 8.4,
            voteCount: 2143,
            inProduction: true,
            homepage: "https://tv.apple.com/show/severance",
            originalLanguage: "en"
        )
    }()

    /// Full TMDB movie details.
    static let sampleMovieDetails = MovieDetails(
        id: 693134,
        title: "Dune: Part Two",
        overview: "Follow the mythic journey of Paul Atreides as he unites with Chani and the Fremen while on a path of revenge against the conspirators who destroyed his family.",
        tagline: "Long live the fighters.",
        posterPath: "/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg",
        backdropPath: "/xOMo8BRK7PfcJv9JCnx7s5hj0PX.jpg",
        releaseDate: CivilDate(year: 2024, month: 3, day: 1),
        runtime: 167,
        genres: [
            Genre(id: 878, name: "Science Fiction"),
            Genre(id: 12, name: "Adventure")
        ],
        status: "Released",
        voteAverage: 8.2,
        voteCount: 5320,
        homepage: "https://www.dunemovie.com",
        originalLanguage: "en",
        imdbID: "tt15239678"
    )

    /// Where Severance can be watched in a few regions.
    static let sampleWatchProviders: WatchProviders = {
        let appleTVPlus = WatchProvider(
            id: 350,
            name: "Apple TV+",
            logoPath: "/2E03IAZsX4ZaUqM7tXlctEPMGWS.jpg",
            displayPriority: 3
        )
        let appleTVPlusAmazon = WatchProvider(
            id: 2552,
            name: "Apple TV+ Amazon Channel",
            logoPath: "/6r8CGxB1oNmM5rlQcYhaiL8gI0Y.jpg",
            displayPriority: 44
        )
        let appleTV = WatchProvider(
            id: 2,
            name: "Apple TV",
            logoPath: "/9ghgSC0MA082EL6HLCW3GalykFD.jpg",
            displayPriority: 5
        )
        return WatchProviders(
            id: 95396,
            regions: [
                "US": RegionWatchProviders(
                    region: "US",
                    link: URL(string: "https://www.themoviedb.org/tv/95396-severance/watch?locale=US"),
                    flatrate: [appleTVPlus, appleTVPlusAmazon],
                    buy: [appleTV]
                ),
                "GB": RegionWatchProviders(
                    region: "GB",
                    link: URL(string: "https://www.themoviedb.org/tv/95396-severance/watch?locale=GB"),
                    flatrate: [appleTVPlus]
                )
            ]
        )
    }()

    // MARK: Private helpers

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date? {
        CivilDate(year: year, month: month, day: day).startOfDay()
    }
}
