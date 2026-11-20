package com.github.eprendre.tingshu.utils

data class Book(
    var coverUrl: String,//封面链接
    val bookUrl: String,//书籍链接
    var title: String,//标题
    var author: String,//作者
    var artist: String//演播
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
    var hasFullEpisodes: Boolean = false//只有 source 的 isMultipleEpisodePages 为 true 时，这个属性才起作用。
    var isShowBriefChapterTitle: Boolean = false
    var sourceId: String? = null
    var status: String = ""
    var episodesUpdateTime: Long = 0
    var isTransientEpisodes: Boolean = false
    var isCompleted: Boolean = false//是否已完结，如果是，app里面将不再触发章节列表的自动刷新。

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is Book) return false
        return bookUrl == other.bookUrl && sourceId == other.sourceId
    }

    override fun hashCode(): Int = bookUrl.hashCode() * 31 + (sourceId?.hashCode() ?: 0)

    fun copyFrom(book: Book) {
        coverUrl = book.coverUrl
        title = book.title
        author = book.author
        artist = book.artist
        intro = book.intro
        id = book.id
        sourceId = book.sourceId
        episodeList = book.episodeList
        status = book.status
    }
}

data class Episode(val title: String, val url: String) {
    var isFree: Boolean = true
    @Transient var isCached: Boolean = false
    var progress: Int = 0
    var coverUrl: String = ""//章节封面
    var transcript: String = ""//文稿，可以传网址，将打开网页。也可以传文本，则打开一个文本框，文本可以用html标签格式。
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
) {
    val title: String = ""
}


/**
 * 大分类
 */
data class CategoryMenu(
    val title: String, //大分类标题
    val tabs: List<CategoryTab>//子分类
) : IMenu {

    override fun getType(): Int = 0

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is CategoryMenu) return false
        return title == other.title && tabs == other.tabs
    }

    override fun hashCode(): Int = title.hashCode() * 31 + tabs.hashCode()
}

data class Category(
    val list: List<Book>,
    val currentPage: Int,
    val totalPage: Int,
    val currentUrl: String,
    val nextUrl: String
)

/**
 * 2.5.9 加入，供自定义源配置文件使用, 可通过ExternalSourcePrefs.getString("${getSourceId()}.${configItem.key}")读取对应的值
 * Switch 读取值为 "true" 或者 "false"
 * MultiSelect 读取值为 "," 分隔的字符串，比如"1,2,3"
 */
sealed class ConfigItem(
    val key: String,
    val label: String
) {
    class Button(label: String, val click: () -> Unit) : ConfigItem("", label)//2.6.0加入
    class Text(key: String, label: String, var default: String = "") : ConfigItem(key, label)
    class Select(key: String, label: String, val options: List<String>, var default: String) : ConfigItem(key, label)
    class Switch(key: String, label: String, var default: Boolean) : ConfigItem(key, label)
    class MultiSelect(key: String, label: String, val options: List<String>, var default: List<String> = listOf()) : ConfigItem(key, label)
}