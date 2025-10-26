@MainActor
protocol CoordinatorProtocol: AnyObject {
    var childCoordinators: [CoordinatorProtocol] { get set }
}

@MainActor
extension CoordinatorProtocol {
    func append(child: CoordinatorProtocol) {
        childCoordinators.append(child)
    }

    func remove(child: CoordinatorProtocol) {
        childCoordinators.removeAll { $0 === child }
    }
}
