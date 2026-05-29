import SwiftData
import SwiftUI

struct AppModelContainerLoader {
    typealias ContainerFactory = () throws -> ModelContainer

    private let makeContainer: ContainerFactory

    init(makeContainer: @escaping ContainerFactory) {
        self.makeContainer = makeContainer
    }

    static func live() -> AppModelContainerLoader {
        AppModelContainerLoader {
            #if DEBUG
            if AppLaunchConfiguration.forcesModelContainerFailure {
                throw ForcedModelContainerFailure()
            }
            #endif

            return try DaaiZekBroSchema.makeModelContainer(
                isStoredInMemoryOnly: AppLaunchConfiguration.isUITesting
            )
        }
    }

    func load() -> Result<ModelContainer, AppStartupFailure> {
        do {
            return .success(try makeContainer())
        } catch {
            return .failure(AppStartupFailure(error: error))
        }
    }
}

struct AppStartupFailure: Error, Equatable {
    let title = "无法打开本地数据"
    let message = "应用启动时无法初始化本地数据库。你的本地训练数据没有被自动擦除或重置，请保留以下诊断信息。"
    let diagnosticMessage: String

    init(error: Error) {
        let nsError = error as NSError
        diagnosticMessage = "\(nsError.domain) (\(nsError.code)): \(error.localizedDescription)"
    }
}

struct ModelContainerFailureView: View {
    let failure: AppStartupFailure

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: DZMetric.space5) {
                    ContentUnavailableView {
                        Label(failure.title, systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(failure.message)
                    }
                    .accessibilityIdentifier("model-container-failure-screen")

                    VStack {
                        Text(failure.diagnosticMessage)
                            .font(.footnote.monospaced())
                            .foregroundStyle(DZColor.ink700)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                    .padding(DZMetric.space4)
                    .frame(maxWidth: 520)
                    .background(DZColor.cream100)
                    .clipShape(RoundedRectangle(cornerRadius: DZMetric.radiusSM, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(failure.diagnosticMessage)
                    .accessibilityIdentifier("model-container-failure-diagnostic")
                }
                .padding(DZMetric.space6)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .center)
            }
            .background(DZColor.cream50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DZColor.cream50)
    }
}

#if DEBUG
private struct ForcedModelContainerFailure: LocalizedError {
    var errorDescription: String? {
        "Forced ModelContainer failure for diagnostic validation."
    }
}
#endif
