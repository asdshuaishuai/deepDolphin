// ColorSampleSheet.h — **状态色样张**（批 R 新增）：把每一档语义色画成一张可核对的色卡。
//
// 【为什么要有这个】
//   批 R 改的是状态语义色的**取值**（停滞红→灰、非 git 紫→灰、unknown 灰→红、
//   分支 stale 红→橙）。但 4 页面板快照基线拍的是**空态**（本机引擎注册项目数 0，
//   快照里只有「仪表盘还没有数据」）—— 状态点一个都没画进去。
//   ⇒ 面板快照对状态色是**空门**：改色它不红，说「视觉已评审」是假的。
//   这张色卡把**每一档**都画出来，纳入截图矩阵 —— 改色 ⇒ 色卡 diff 红；
//   同时它是跨端对齐的**人工核对凭据**（对着 mac 的同名档逐行看）。
//
// 【⚠ 它不是产品界面】
//   只由无头入口 `--color-sample <out.png>` 拉起，不挂菜单、不进设置页。
//   颜色**全部**从判定层取（`Derived::livenessColor` / `branchStatusColor` /
//   `logic/SemColors`）—— 判定层改色，这里自动跟着变。
//   ⚠ 本控件**不许**自己写死任何色值（那就是第二份定义了）。
#pragma once

#include <QWidget>

/// 状态色样张。固定尺寸（拍快照要比对，尺寸不能飘）。
class ColorSampleSheet : public QWidget {
public:
    explicit ColorSampleSheet(QWidget *parent = nullptr);

    // ⚠ 高度**按内容算足**（7 + 5 + 4 行 + 4 个小标题 + 边距 ≈ 710）——
    //   留小了底行会被裁掉，样张就少画一档（少画的那档 = 基线里没有 = 又一个空门）。
    QSize sizeHint() const override { return { 900, 720 }; }

protected:
    void paintEvent(QPaintEvent *event) override;

private:
    /// 画一组「色块 + 名称 + 取值」的行。
    void drawRow(QPainter &p, int y, const QColor &c, const QString &name, const QString &note);
};
