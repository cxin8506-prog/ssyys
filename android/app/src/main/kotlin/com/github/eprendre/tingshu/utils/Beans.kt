package com.github.eprendre.tingshu.utils

/** 与「我的听书」SDK 对齐的数据类，字段顺序会影响 JAR 里的构造调用，不要改。 */
data class Book(
    var coverUrl: String,
    val bookUrl: String,
    val title: String,
    var author: String,
    var artist: String
) {
    var id: Int? = null
    var intro: String = ""
    var currentEpisodeUrl: String? = null
    var currentEpisodeName: String? = null
    var currentEpisodePosition: Long = 0
    var skipBeginning: Long = 0
    var skipEnd: Long = 0
    var volumeBoostLevel: Int = 0
    var playOrderType: Int = 0
    var playSpeed: Float = 1f
    var isFree: Boolean = true
    var isEpisodesReversed: Boolean = false
    var episodeList: List<Episode>? = null
    var hasFullEpisodes: Boolean = false
    var isShowBriefChapterTitle: Boolean = false
    var sourceId: String? = null
    var status: String = ""

    fun copyFrom(book: Book) {
        coverUrl = book.coverUrl
        author = book.author
        artist = book.artist
        intro = book.intro
        episodeList = book.episodeList
        status = book.status
    }
}

data class Episode(val title: String, val url: String) {
    var isFree: Boolean = true
    var isCached: Boolean = false
    var progress: Int = 0
}

interface IMenu {
    fun getType(): Int
}

data class CategoryTab(
    val title: String,
    val url: String
) : IMenu {
    override fun getType(): Int = 0
}

data class BookDetail(
    val playList: List<Episode>,
    val intro: String? = "",
    val artist: String = "",
    val author: String = "",
    val episodesCount: Int = 0,
    val coverUrl: String = ""
)

data class CategoryMenu(
    val title: String,
    val tabs: List<CategoryTab>
) : IMenu {
    override fun getType(): Int = 1
}

data class Category(
    val list: List<Book>,
    val currentPage: Int,
    val totalPage: Int,
    val currentUrl: String,
    val nextUrl: String
)
