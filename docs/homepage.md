# 项目主页

项目主页是面向玩家的中文静态介绍页，包含联机特点、安装入口、连接要求和常见问题。源码位于 [site/](https://github.com/BMingSY/isaac-lan/tree/main/site)，不依赖前端框架、外部字体、运行时 API 或游戏进程；下载入口始终指向 GitHub 最新正式 Release。

## 本地预览

在仓库根目录执行：

```sh
python3 tools/build_site.py
python3 -m http.server 8080 --directory dist/site
```

浏览器打开 `http://localhost:8080`。构建工具只重建 `dist/site`，复制静态文件与现有工坊封面；不重复保存封面源文件。页面资源使用相对路径，可部署于 GitHub Pages 的仓库子路径。关闭 JavaScript 时，正文、下载链接、安装说明和原生 FAQ 折叠面板仍可使用；楼层示意保留默认分房视图。

## GitHub Pages

仓库的 Pages 发布来源为 **GitHub Actions**。主页或共享封面合并到 `main` 后会触发 [pages.yml](https://github.com/BMingSY/isaac-lan/blob/main/.github/workflows/pages.yml)；也可从 Actions 手动运行 **GitHub Pages** 工作流。只有 `main` 分支可以部署，PR 不发布站点。默认地址为 `https://bmingsy.github.io/isaac-lan/`，实际地址以部署环境输出为准。

工作流仅上传 `dist/site`，使用 GitHub 提供的 Pages 与 OIDC 权限，无需额外令牌。网站目录之外的文档、安装包和游戏代码不会作为站点文件发布。

## 内容维护

主页的功能与操作说明以 [README](https://github.com/BMingSY/isaac-lan/blob/main/README.md)、[FAQ](https://github.com/BMingSY/isaac-lan/blob/main/docs/faq.md) 和 [Mod 兼容清单](https://github.com/BMingSY/isaac-lan/blob/main/docs/mod-compatibility.md) 为依据。更新游戏版本、安装要求或联机能力时同步核对主页；具体契约与详细操作继续链接到对应文档，不在主页维护完整副本。
