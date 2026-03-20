/**
 * [INPUT]: 依赖 UIKit、SwiftUI
 * [OUTPUT]: 对外提供 KeyboardViewController，UIInputViewController 子类，宿主 SwiftUI 键盘 UI
 * [POS]: VoiceFlowKeyboard Extension 的入口控制器
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import UIKit
import SwiftUI

// ========================================
// MARK: - Keyboard View Controller
// ========================================

final class KeyboardViewController: UIInputViewController {

    private var host: UIHostingController<KeyboardView>?
    private var viewModel: KeyboardViewModel?

    override func viewDidLoad() {
        super.viewDidLoad()

        // ----------------------------------------
        // MARK: - 固定键盘高度
        // ----------------------------------------

        // priority 999 而非 required(1000)：允许系统在初始化时临时覆盖高度
        // 避免 UIView-Encapsulated-Layout-Height 冲突警告
        let height = view.heightAnchor.constraint(equalToConstant: 260)
        height.priority = UILayoutPriority(999)
        height.isActive = true

        // ----------------------------------------
        // MARK: - SwiftUI 宿主
        // ----------------------------------------

        let vm = KeyboardViewModel(inputVC: self)
        self.viewModel = vm

        let hosting = UIHostingController(rootView: KeyboardView(viewModel: vm))
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear

        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        host = hosting
    }

    // ----------------------------------------
    // MARK: - 从主 App 返回时检测结果
    // ----------------------------------------

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 用户从主 App 返回键盘时，检查是否有待插入的文字
        viewModel?.onReturnFromMainApp()
    }
}
