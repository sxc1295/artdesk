# 第三方来源与图片许可

MIT 许可适用于本项目代码和项目自身撰写的使用文档。它不改变艺术作品图像、博物馆元数据、馆方文本或 JBS 软件各自适用的许可。

## 作品清单

`data/artworks.json` 是逐幅来源清单，包含作品编号、作者、标题、馆藏、作品页面、原图来源（如原记录提供）、图片许可和 SHA256。Release 内的图片与该清单一一对应。原目录中许可不明确的 38 幅未纳入首版公开包。

395 幅的现有记录分布为：克利夫兰艺术博物馆 276 幅（CC0）、美国国家美术馆 80 幅（CC0）、荷兰国立博物馆 30 幅（公共领域图片 / CC0 元数据）、维基共享资源 7 幅（公共领域）、大都会艺术博物馆 2 幅（馆方标注公共领域）。这份分布来自项目既有来源记录；没有把“可在线浏览”当作可重新分发的许可。

- [克利夫兰艺术博物馆 Open Access](https://www.clevelandart.org/open-access)：公开领域作品的开放图像及数据标注 CC0。
- [大都会艺术博物馆 Open Access](https://www.metmuseum.org/hubs/open-access)：开放图像及基础数据遵循馆方的 CC0 项目。
- [美国国家美术馆开放政策](https://www.nga.gov/terms-and-notices)：馆方开放图像采用 CC0；本库 80 幅均指向官方图像源。已抽查部分作品页，没有重新逐幅复核全部图像。
- [荷兰国立博物馆数据政策](https://data.rijksmuseum.nl/policy/)：标记 Public Domain Mark 或 CC0 的材料可以再利用。馆中也有受限作品；本库 30 幅根据既有逐幅许可记录筛选，并抽查部分作品页。

维基共享资源图像许可页：

- [星月夜](https://commons.wikimedia.org/wiki/File:Van_Gogh_-_Starry_Night_-_Google_Art_Project.jpg)
- [梦](https://commons.wikimedia.org/wiki/File:Henri_Rousseau_005.jpg)
- [沉睡的吉卜赛人](https://commons.wikimedia.org/wiki/File:La_Boh%C3%A9mienne_endormie.jpg)
- [白上白](https://commons.wikimedia.org/wiki/File:White_on_White_%28Malevich%2C_1918%29.png)
- [城市兴起](https://commons.wikimedia.org/wiki/File:The_City_Rises_by_Umberto_Boccioni_1910.jpg)
- [统舱](https://commons.wikimedia.org/wiki/File:Alfred_Stieglitz_-_The_Steerage_-_Google_Art_Project.jpg)
- [德累斯顿街景](https://commons.wikimedia.org/wiki/File:Kirchner_-_Die_Stra%C3%9Fe.jpg)

上述 7 个页面于 2026-10-13 核实均有公共领域声明。《德累斯顿街景》页同时有“缺少美国公共领域标签”的维护提示；保留这一来源局限，不把来源声明扩大为全球无条件免版权保证。

中文简介依据原目录及馆藏页整理，部分简介有馆方信息核对，部分仅有基础资料；`sourceNote` / `verificationLevel` 保留核验说明。欣赏提示为编辑建议，不代表馆方观点或认证。来源文本及其整理内容不被本项目重新声明为 MIT 授权。

本项目与任何博物馆、艺术家或 JBS 作者均无官方合作或背书关系。

## JBS

[John’s Background Switcher for Windows](https://johnsad.ventures/software/backgroundswitcher/windows/) 由 John’s Adventures 提供。项目不附带其安装包、程序或许可文件，不宣称它属于本项目的开源代码。用户自行从官网下载并按其条款使用。

## 开发依赖

正常运行使用 Windows 内置 PowerShell / .NET 和 Microsoft Edge。只有开发时重建缩略图才使用 Pillow；它不随完整使用包分发。Pillow 的许可可在 [官方仓库](https://github.com/python-pillow/Pillow/blob/main/LICENSE) 查看。
