import Foundation

/// The two legal documents the app shows: Profile › DATA & LEGAL, the membership card's ⋯ menu,
/// and the sign-in line. Both languages live here rather than in `zh-Hans.json`: a document is
/// read as a whole, and a clause that is translated in one place and not another is worse than
/// no translation at all.
///
/// ⚠️ Every factual claim below is a claim about the code. When a retention window, a processor,
/// or a data type changes, this file changes in the same commit, and `updated` moves with it.
/// Checked against the tree on 2026-09-22: Supabase (AWS us-west-1) · xAI Grok primary, Alibaba
/// Cloud Model Studio (Qwen) fallback, speech and web search · RevenueCat · GitHub (private repo)
/// for REPORT A PROBLEM · photos 30 days · voice never stored · analytics 180 days · AI screen
/// frames 90 days · overnight oxygen and meal response samples 400 days · account eligibility is separate from content ratings.
/// The consent screen (`ConsentCopy`) is a separate, versioned text and is not folded in here.
enum LegalText {
    struct Section {
        let heading: String
        let paragraphs: [String]
    }

    struct Document {
        let title: String
        let updated: String
        let sections: [Section]
    }

    enum Kind { case terms, privacy }

    static let updatedEN = "Last updated September 22, 2026"
    static let updatedZH = "最后更新：2026 年 9 月 22 日"

    static func document(_ kind: Kind, locale: AppLocale = AppLanguage.shared.locale) -> Document {
        switch (kind, locale) {
        case (.terms, .simplifiedChinese):   Document(title: "服务条款", updated: updatedZH, sections: termsZH)
        case (.terms, _):                    Document(title: "Terms of Service", updated: updatedEN, sections: termsEN)
        case (.privacy, .simplifiedChinese): Document(title: "隐私政策", updated: updatedZH, sections: privacyZH)
        case (.privacy, _):                  Document(title: "Privacy Policy", updated: updatedEN, sections: privacyEN)
        }
    }

    // MARK: - Terms of Service · English

    static let termsEN: [Section] = [
        Section(heading: "1. These terms", paragraphs: [
            "These Terms of Service (\"Terms\") are a binding agreement between you and NextBody (\"NextBody\", \"we\", \"us\") for the NextBody app, your account, NextBody Pro, and any HOOP band you pair with the app (together, the \"Service\"). Our Privacy Policy explains how we handle your data and forms part of these Terms.",
            "By creating an account, signing in, or using the Service, you confirm that you have read and accept these Terms. If you do not accept them, do not use the Service.",
            "PLEASE READ SECTIONS 4, 5, 13, 14 AND 17 CAREFULLY. THEY LIMIT OUR LIABILITY, DESCRIBE THE RISKS YOU ACCEPT, AND EXPLAIN HOW DISPUTES ARE RESOLVED.",
        ]),
        Section(heading: "2. Who may use the Service", paragraphs: [
            "You must be at least 16 years old and meet any higher minimum age required to consent to this Service and the processing of your health data where you live. If you have not reached the age of legal adulthood, a parent or legal guardian must review and agree to these Terms and supervise your use. The Service is not directed to children under 16. App Store content ratings do not replace these account eligibility requirements.",
            "You may not use the Service if the law where you live forbids it, or if we have previously closed your account for breaking these Terms.",
        ]),
        Section(heading: "3. Your account", paragraphs: [
            "You sign in with Apple, Google, or a one-time code sent to your email. One account belongs to one person. Keep your devices and sign-in methods secure: you are responsible for everything done through your account, and we are not liable for loss caused by someone using your account or device.",
            "Tell us at once at shop@nextbody.ai if you believe your account has been compromised. The information you give us, including your sex, date of birth, height and weight, must be accurate; the calculations depend on it.",
        ]),
        Section(heading: "4. Not medical advice · not a medical device", paragraphs: [
            "The Service is a general wellness and fitness product. It is not a medical device, and it has not been evaluated, cleared or approved by the FDA, the NMPA, or any other health authority. It is not intended to diagnose, treat, cure, monitor, mitigate or prevent any disease or medical condition.",
            "Every number the Service shows is an estimate. This includes heart rate, heart rate variability, sleep stages and sleep score, overnight blood oxygen, skin temperature, Body Battery, training load, calories burned and eaten, energy targets, body composition, and the wrist optical meal response. These estimates come from consumer sensors and algorithms, can be wrong, incomplete or delayed, and must not be used in place of a measurement by a qualified professional or a medical-grade instrument. Meal response is a unitless index; it is not a blood glucose reading.",
            "Talk to a doctor before you start or change any exercise, diet, fasting, weight-loss or sleep programme, and before you act on anything the Service shows or says, especially if you are pregnant, have a heart, blood pressure, metabolic or sleep condition, an eating disorder or a history of one, a pacemaker or other implanted device, or take medication.",
            "Never ignore or delay professional medical advice because of the Service. It does not watch you, send alerts to anyone, or detect emergencies. If you think you may have a medical emergency, call your local emergency number immediately.",
        ]),
        Section(heading: "5. Exercise and physical activity", paragraphs: [
            "Exercise, training, dieting and changes in eating or sleeping carry an inherent risk of injury, illness and, in rare cases, death. You choose whether, how and how hard to exercise, and you do so voluntarily and at your own risk. Stop immediately and seek medical help if you feel pain, faintness, dizziness, shortness of breath or chest discomfort.",
            "To the fullest extent permitted by law, you assume all risks arising from your physical activity and from your decisions about food, weight and sleep, whether or not they were prompted by the Service.",
        ]),
        Section(heading: "6. AI features", paragraphs: [
            "NextBody Pro uses artificial intelligence, including large language models run by third-party providers, to answer questions, write plans and daily suggestions, estimate meals from words or photos, transcribe your voice, remember things you tell it, and search the web. AI output is generated automatically and is not reviewed by a person before you see it.",
            "AI output can be inaccurate, incomplete, out of date, inconsistent, or inappropriate, and may state wrong things with confidence. Meal and calorie estimates from photos or descriptions are approximate. Web search results come from third-party websites that we do not control or endorse.",
            "AI output is for general information only. It is not medical, nutritional, dietetic, psychological, fitness-coaching, legal or other professional advice, and it does not create any professional relationship. You are solely responsible for checking it and for any decision you make based on it.",
            "Do not ask the AI for, or rely on it in, an emergency. Do not submit other people's personal information, or anything unlawful. AI features are subject to fair-use limits, including daily allowances, and may be slowed, limited or unavailable at any time.",
        ]),
        Section(heading: "7. The HOOP band and other devices", paragraphs: [
            "A HOOP band bought from us is covered by the shop's Terms of Service, Refund Policy and any written warranty that came with it; these Terms cover how the band works with the app. The band's hardware and firmware are made by a third-party manufacturer.",
            "Readings depend on fit, skin, movement, battery, Bluetooth, the phone's operating system and the band's firmware. We do not promise that every reading will be captured, synced, or kept, and readings not yet synced from the band can be lost.",
            "Follow the band's safety and charging instructions. Stop wearing it if your skin becomes irritated. Remove it before MRI scans and anywhere metal or electronics are not allowed.",
        ]),
        Section(heading: "8. NextBody Pro subscription", paragraphs: [
            "The band's core readings work without a subscription. NextBody Pro, which unlocks the AI features, is an auto-renewing subscription sold and billed by Apple through the App Store. The price, billing period and any free trial are shown to you in the App Store before you confirm the purchase, and may differ by country.",
            "Your subscription renews automatically at the end of each period unless you turn off auto-renew at least 24 hours before the period ends, in your Apple ID's subscription settings. Deleting the app or your account does not cancel an App Store subscription. If you are offered a free trial, eligibility is decided by Apple, and any unused part of a trial ends when you buy a subscription.",
            "All payments, cancellations and refunds are handled by Apple under Apple's terms. We do not process your payment, cannot see your card details, and cannot issue refunds for App Store purchases. To the extent permitted by law, fees paid are non-refundable, including for partial periods or unused features.",
            "We may change what Pro includes, its limits, or its price. Price changes follow App Store rules, and Apple will tell you before a higher price applies.",
        ]),
        Section(heading: "9. Acceptable use", paragraphs: [
            "You agree not to: use the Service for anyone but yourself; resell or share access; copy, scrape, reverse engineer, decompile or interfere with the app, the band's firmware or our servers, except where the law expressly allows it; overload or probe the Service or bypass its limits, rate limits or security; use the AI to produce unlawful, harmful, harassing or infringing content; use the Service to give medical, nutritional or training advice to others as a professional service; or break any law.",
            "We may investigate misuse, and may limit, suspend or close an account that breaks these Terms or puts the Service, other users or us at risk, with or without notice where the law allows.",
        ]),
        Section(heading: "10. Your content and feedback", paragraphs: [
            "You keep ownership of the readings, meals, photos, messages and other content you provide (\"Your Content\"). You give us a worldwide, non-exclusive, royalty-free licence to host, store, copy, process, transmit and display Your Content, including sending it to our service providers, only as needed to run, secure, support and improve the Service and as described in the Privacy Policy. The licence ends when Your Content is deleted, except for copies we must keep by law.",
            "You are responsible for Your Content and confirm you have the right to submit it. If you send us ideas, suggestions or problem reports, we may use them freely without any obligation to you.",
        ]),
        Section(heading: "11. Our rights", paragraphs: [
            "The app, its software, design, text, graphics, algorithms and trademarks belong to NextBody or its licensors. We grant you a personal, limited, revocable, non-exclusive, non-transferable licence to use the app on Apple devices you own or control, for your own non-commercial use, under these Terms and the App Store's rules. Everything not expressly granted is reserved.",
        ]),
        Section(heading: "12. Third-party services", paragraphs: [
            "The Service relies on services we do not control, including Apple (App Store, Sign in with Apple, Apple Health), Google, AI model providers, hosting providers, and websites returned by web search. Your use of them is governed by their own terms. We are not responsible for their content, availability, accuracy or practices, or for any loss they cause.",
        ]),
        Section(heading: "13. Disclaimer of warranties", paragraphs: [
            "TO THE FULLEST EXTENT PERMITTED BY LAW, THE SERVICE, ALL READINGS, SCORES, ESTIMATES AND AI OUTPUT ARE PROVIDED \"AS IS\" AND \"AS AVAILABLE\", WITH ALL FAULTS AND WITHOUT WARRANTY OF ANY KIND, WHETHER EXPRESS, IMPLIED OR STATUTORY, INCLUDING ANY WARRANTY OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, ACCURACY, QUIET ENJOYMENT, OR NON-INFRINGEMENT.",
            "WE DO NOT WARRANT THAT THE SERVICE WILL BE UNINTERRUPTED, TIMELY, SECURE OR ERROR-FREE, THAT ANY DATA WILL BE ACCURATE, COMPLETE OR PRESERVED, THAT DEFECTS WILL BE CORRECTED, OR THAT THE SERVICE WILL ACHIEVE ANY HEALTH, FITNESS, WEIGHT OR OTHER RESULT. We may change, suspend or discontinue any part of the Service at any time.",
        ]),
        Section(heading: "14. Limitation of liability", paragraphs: [
            "TO THE FULLEST EXTENT PERMITTED BY LAW, NEXTBODY AND ITS AFFILIATES, OFFICERS, EMPLOYEES, CONTRACTORS, SUPPLIERS AND LICENSORS WILL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY OR PUNITIVE DAMAGES, OR FOR ANY LOSS OF PROFITS, REVENUE, DATA, GOODWILL OR HEALTH OUTCOME, OR COST OF SUBSTITUTE SERVICES, ARISING OUT OF OR RELATING TO THE SERVICE OR THESE TERMS, WHETHER IN CONTRACT, TORT (INCLUDING NEGLIGENCE), PRODUCT LIABILITY OR ANY OTHER THEORY, EVEN IF WE WERE TOLD SUCH DAMAGES WERE POSSIBLE.",
            "TO THE FULLEST EXTENT PERMITTED BY LAW, OUR TOTAL LIABILITY FOR ALL CLAIMS ARISING OUT OF OR RELATING TO THE SERVICE OR THESE TERMS IS LIMITED TO THE GREATER OF (A) THE AMOUNT YOU PAID FOR NEXTBODY PRO IN THE 12 MONTHS BEFORE THE EVENT GIVING RISE TO THE CLAIM, AND (B) USD 50. A HOOP BAND YOU BOUGHT IS SUBJECT TO THE LIMITS IN THE SHOP'S TERMS.",
            "Some places do not allow certain warranties to be excluded or liability to be limited. Nothing in these Terms excludes or limits liability for death or personal injury caused by our negligence, for fraud, for intentional misconduct or gross negligence, or any other liability or consumer right that cannot be excluded or limited by law. In those places, our liability is limited to the smallest extent the law permits.",
        ]),
        Section(heading: "15. Indemnity", paragraphs: [
            "To the extent permitted by law, you will defend, indemnify and hold harmless NextBody and its affiliates, officers, employees and contractors from any claim, loss, liability, damage, cost or expense (including reasonable legal fees) arising from your breach of these Terms, your misuse of the Service, Your Content, or your violation of any law or anyone else's rights.",
        ]),
        Section(heading: "16. Ending this agreement", paragraphs: [
            "You can stop using the Service at any time and delete your account in Profile › Data & Legal › Delete account. Remember to cancel NextBody Pro in the App Store separately.",
            "We may suspend or end your access at any time if you break these Terms, if we must by law, or if we stop offering the Service or part of it. If we discontinue the Service entirely, we will try to give reasonable notice. Sections 4, 5, 6, 10 and 12 to 19 survive the end of this agreement.",
        ]),
        Section(heading: "17. Disputes", paragraphs: [
            "Before bringing any claim, you agree to write to shop@nextbody.ai describing it and to give us 60 days to try to resolve it informally.",
            "These Terms are governed by the laws of the place where NextBody is established, without regard to its conflict-of-law rules, and the courts of that place have jurisdiction, except where the consumer law of the country where you live gives you the right to have that law apply or to bring proceedings in your local courts.",
            "To the extent permitted by law, any claim must be brought within one year after it arises, and only on an individual basis, not as a plaintiff or class member in any class, collective or representative action.",
        ]),
        Section(heading: "18. Changes to these Terms", paragraphs: [
            "We may update these Terms from time to time. The date at the top shows the latest version. If a change is material, we will tell you in the app before it takes effect. If you keep using the Service after a change takes effect, you accept the updated Terms; if you do not accept them, stop using the Service and delete your account.",
        ]),
        Section(heading: "19. General", paragraphs: [
            "These Terms and the Privacy Policy are the entire agreement between you and us about the Service. If any part is found unenforceable, it will be enforced to the maximum extent possible and the rest remains in effect. Our failure to enforce a right is not a waiver of it. You may not transfer these Terms; we may transfer them in connection with a merger, acquisition, or sale of assets. We are not liable for any delay or failure caused by events beyond our reasonable control. If a translation of these Terms conflicts with the English version, the English version controls unless the law requires otherwise.",
        ]),
        Section(heading: "20. Apple", paragraphs: [
            "These Terms are between you and NextBody only, not Apple. Apple is not responsible for the app or its content, and has no obligation to provide maintenance or support for it. If the app fails to conform to any applicable warranty, you may notify Apple and Apple will refund the purchase price of the app, if any; to the maximum extent permitted by law, Apple has no other warranty obligation for the app.",
            "Apple is not responsible for addressing any claims relating to the app, including product liability claims, claims that the app fails to meet any legal or regulatory requirement, consumer protection or privacy claims, or claims that the app infringes a third party's intellectual property. You confirm you are not located in a country subject to a U.S. Government embargo or designated as supporting terrorism, and are not on any U.S. Government list of prohibited or restricted parties. Apple and its subsidiaries are third-party beneficiaries of these Terms and may enforce them against you.",
        ]),
        Section(heading: "21. Contact", paragraphs: [
            "Questions about these Terms: shop@nextbody.ai. Questions about your data: privacy@nextbody.ai.",
        ]),
    ]

    // MARK: - Terms of Service · 中文

    static let termsZH: [Section] = [
        Section(heading: "1. 关于本条款", paragraphs: [
            "本《服务条款》（「本条款」）是你与 NextBody（「NextBody」「我们」）之间就 NextBody App、你的账户、NextBody Pro 以及你与 App 配对的 HOOP 手环（合称「本服务」）订立的具有约束力的协议。《隐私政策》说明我们如何处理你的数据，是本条款的组成部分。",
            "你创建账户、登录或使用本服务，即表示你已阅读并接受本条款。如不接受，请不要使用本服务。",
            "请特别注意第 4、5、13、14、17 条。这些条款限制了我们的责任，说明了你自行承担的风险以及争议的解决方式。",
        ]),
        Section(heading: "2. 谁可以使用", paragraphs: [
            "你必须年满 16 周岁，并满足所在地法律对同意使用本服务及处理健康数据规定的更高最低年龄要求。如果你尚未达到法定成年年龄，父母或法定监护人须审阅并同意本条款，监督你的使用。本服务不面向未满 16 周岁的儿童。App Store 内容年龄分级不能替代这些账户使用资格要求。",
            "如你所在地的法律禁止你使用本服务，或你的账户曾因违反本条款被我们注销，你不得使用本服务。",
        ]),
        Section(heading: "3. 你的账户", paragraphs: [
            "你可以通过 Apple、Google 或发送到邮箱的一次性验证码登录。一个账户只属于一个人。请妥善保管你的设备和登录方式：通过你的账户进行的一切操作都由你负责，他人使用你的账户或设备造成的损失，我们不承担责任。",
            "如你认为账户已被他人控制，请立即写信至 shop@nextbody.ai。你提供的信息（包括性别、出生日期、身高和体重）必须真实准确，各项计算都依赖这些信息。",
        ]),
        Section(heading: "4. 不构成医疗建议 · 不是医疗器械", paragraphs: [
            "本服务是一般性的健康与健身产品，不是医疗器械，未经美国 FDA、中国国家药品监督管理局或任何其他卫生主管部门的评估、注册或批准，不用于诊断、治疗、治愈、监测、缓解或预防任何疾病或健康状况。",
            "本服务显示的所有数字都是估算值，包括心率、心率变异性、睡眠分期与睡眠评分、夜间血氧、皮肤温度、身体电量、训练负荷、消耗与摄入热量、能量目标、身体成分以及腕部光学餐后反应。这些估算来自消费级传感器和算法，可能不准确、不完整或有延迟，不得替代专业人员或医用级仪器的测量。餐后反应是一个无单位指数，不是血糖读数。",
            "开始或调整任何运动、饮食、断食、减重或睡眠方案之前，以及依据本服务显示或给出的任何内容采取行动之前，请先咨询医生。如你怀孕，患有心脏、血压、代谢或睡眠方面的疾病，患有或曾患进食障碍，装有心脏起搏器或其他植入设备，或正在服药，尤其应当如此。",
            "切勿因本服务而忽视或延误专业医疗意见。本服务不会看护你，不会向任何人发出警报，也不会识别紧急情况。如你认为自己可能遇到医疗紧急情况，请立即拨打当地急救电话。",
        ]),
        Section(heading: "5. 运动与身体活动", paragraphs: [
            "运动、训练、节食以及饮食和睡眠习惯的改变，本身就存在受伤、患病乃至极少数情况下死亡的风险。是否运动、怎样运动、运动强度多大，由你自主决定，风险由你自行承担。如感到疼痛、晕厥、头晕、呼吸困难或胸部不适，请立即停止并就医。",
            "在法律允许的最大范围内，你因身体活动以及就饮食、体重和睡眠所作决定而产生的一切风险，无论是否受本服务提示，均由你自行承担。",
        ]),
        Section(heading: "6. AI 功能", paragraphs: [
            "NextBody Pro 使用人工智能（包括由第三方服务商运行的大语言模型）来回答问题、制定计划和每日建议、根据文字或照片估算餐食、将你的语音转成文字、记住你告诉它的事情以及进行网络搜索。AI 输出由系统自动生成，在你看到之前不经过人工审核。",
            "AI 输出可能不准确、不完整、过时、前后不一致或不恰当，也可能以肯定的语气给出错误内容。根据照片或文字得出的餐食和热量估算只是近似值。网络搜索结果来自我们无法控制、也不为其背书的第三方网站。",
            "AI 输出仅供一般参考，不构成医疗、营养、膳食、心理、健身指导、法律或其他任何专业意见，也不在你与任何人之间建立专业服务关系。核实 AI 输出以及据此作出的任何决定，均由你自行负责。",
            "紧急情况下不要向 AI 求助或依赖 AI。不要提交他人的个人信息或任何违法内容。AI 功能设有合理使用限制（包括每日额度），可能随时被降速、限制或暂停。",
        ]),
        Section(heading: "7. HOOP 手环及其他设备", paragraphs: [
            "从我们这里购买的 HOOP 手环适用商店的《服务条款》《退款政策》以及随附的书面保修说明；本条款约束的是手环与 App 配合使用的部分。手环的硬件与固件由第三方制造商生产。",
            "读数受佩戴松紧、皮肤、动作、电量、蓝牙、手机操作系统和手环固件等因素影响。我们不保证每一条读数都会被采集、同步或保存；尚未从手环同步的数据可能丢失。",
            "请遵守手环的安全和充电说明。如皮肤出现不适，请停止佩戴。进行核磁共振检查前，以及在禁止携带金属或电子设备的场所，请取下手环。",
        ]),
        Section(heading: "8. NextBody Pro 订阅", paragraphs: [
            "手环的核心读数无需订阅即可使用。NextBody Pro 用于开启 AI 功能，是由 Apple 通过 App Store 销售和收费的自动续期订阅。价格、计费周期以及可能提供的免费试用，会在你确认购买前显示在 App Store 中，不同国家或地区可能不同。",
            "除非你在当期结束前至少 24 小时在 Apple ID 的订阅设置中关闭自动续期，订阅将在每期结束时自动续订。删除 App 或注销账户不会取消 App Store 订阅。免费试用的资格由 Apple 决定；购买订阅后，试用期中未使用的部分即告结束。",
            "所有付款、取消和退款均由 Apple 按其条款处理。我们不处理你的付款，看不到你的银行卡信息，也无法为 App Store 购买办理退款。在法律允许的范围内，已支付的费用不予退还，包括未满一期或未使用的功能。",
            "我们可能调整 Pro 包含的内容、使用限制或价格。价格调整遵守 App Store 规则，涨价生效前 Apple 会通知你。",
        ]),
        Section(heading: "9. 使用规范", paragraphs: [
            "你同意不会：将本服务用于你本人以外的任何人；转售或共享访问权限；复制、抓取、反向工程、反编译或干扰 App、手环固件或我们的服务器（法律明确允许的除外）；使本服务过载、对其进行探测，或绕过其限制、频率限制或安全措施；利用 AI 生成违法、有害、骚扰或侵权内容；利用本服务以专业服务的名义向他人提供医疗、营养或训练建议；或违反任何法律。",
            "我们可以调查滥用行为，并可以对违反本条款、或使本服务、其他用户或我们面临风险的账户进行限制、暂停或注销；在法律允许的情况下，可不事先通知。",
        ]),
        Section(heading: "10. 你的内容与反馈", paragraphs: [
            "你提供的读数、餐食、照片、消息及其他内容（「你的内容」）归你所有。你授予我们一项全球范围内、非独占、免费的许可，仅在运行、保护、支持和改进本服务所需的范围内，并按《隐私政策》所述，托管、存储、复制、处理、传输和显示你的内容，包括将其发送给我们的服务商。你的内容被删除后，该许可随之终止，但法律要求我们保留的副本除外。",
            "你对你的内容负责，并确认你有权提交这些内容。你向我们提出的想法、建议或问题反馈，我们可以自由使用，且不对你负有任何义务。",
        ]),
        Section(heading: "11. 我们的权利", paragraphs: [
            "App 及其软件、设计、文字、图形、算法和商标归 NextBody 或其许可方所有。我们授予你一项个人的、有限的、可撤销的、非独占且不可转让的许可，允许你按照本条款和 App Store 规则，在你拥有或控制的 Apple 设备上为个人非商业目的使用 App。未明确授予的权利均予保留。",
        ]),
        Section(heading: "12. 第三方服务", paragraphs: [
            "本服务依赖我们无法控制的服务，包括 Apple（App Store、通过 Apple 登录、Apple 健康）、Google、AI 模型服务商、托管服务商以及网络搜索返回的网站。你对这些服务的使用受其各自条款约束。对于它们的内容、可用性、准确性或做法，以及由它们造成的任何损失，我们不承担责任。",
        ]),
        Section(heading: "13. 免责声明", paragraphs: [
            "在法律允许的最大范围内，本服务以及所有读数、评分、估算和 AI 输出均按「现状」和「现有」基础提供，可能存在各种缺陷，我们不作任何明示、默示或法定的保证，包括但不限于对适销性、特定用途适用性、准确性、不受干扰使用或不侵权的保证。",
            "我们不保证本服务不中断、及时、安全或没有错误，不保证任何数据准确、完整或得到保存，不保证缺陷会被修复，也不保证本服务能帮助你达成任何健康、健身、体重或其他结果。我们可以随时变更、暂停或终止本服务的任何部分。",
        ]),
        Section(heading: "14. 责任限制", paragraphs: [
            "在法律允许的最大范围内，对于因本服务或本条款引起或与之相关的任何间接、附带、特殊、后果性、惩戒性或惩罚性损害，或任何利润、收入、数据、商誉、健康结果的损失或替代服务的费用，无论基于合同、侵权（包括过失）、产品责任或其他任何理由，即使我们已被告知可能发生此类损害，NextBody 及其关联方、管理人员、员工、承包商、供应商和许可方均不承担责任。",
            "在法律允许的最大范围内，我们因本服务或本条款引起或与之相关的全部索赔所承担的责任总额，以下列两者中较高者为限：（一）引起索赔的事件发生前 12 个月内你为 NextBody Pro 支付的金额；（二）50 美元。你购买的 HOOP 手环适用商店条款中的责任限制。",
            "部分国家或地区不允许排除某些保证或限制责任。本条款不排除或限制我们对因我们的过失造成的人身伤亡、欺诈、故意或重大过失造成的财产损失所应承担的责任，也不排除或限制法律规定不得排除或限制的任何其他责任或消费者权利。在这些地区，我们的责任在法律允许的范围内予以最大限度的限制。",
        ]),
        Section(heading: "15. 赔偿", paragraphs: [
            "在法律允许的范围内，对于因你违反本条款、滥用本服务、你的内容，或你违反任何法律或侵犯他人权利而引起的任何索赔、损失、责任、损害、费用或开支（包括合理的律师费），你应为 NextBody 及其关联方、管理人员、员工和承包商进行抗辩、作出赔偿并使其免受损害。",
        ]),
        Section(heading: "16. 协议终止", paragraphs: [
            "你可以随时停止使用本服务，并在「个人资料 › 数据与法律 › 删除账户」中注销账户。请记得另行在 App Store 中取消 NextBody Pro 订阅。",
            "如你违反本条款、法律要求我们这样做，或我们停止提供本服务或其中部分功能，我们可以随时暂停或终止你的使用。如我们完全停止本服务，会尽量提前合理通知。第 4、5、6、10 条以及第 12 至 19 条在本协议终止后继续有效。",
        ]),
        Section(heading: "17. 争议解决", paragraphs: [
            "在提出任何索赔之前，你同意先写信至 shop@nextbody.ai 说明情况，并给我们 60 天时间尝试协商解决。",
            "本条款适用 NextBody 设立地的法律（不适用其冲突法规则），并由该地法院管辖；但如你所在国家的消费者保护法赋予你适用当地法律或在当地法院起诉的权利，则从其规定。",
            "在法律允许的范围内，任何索赔须在索赔事由发生后一年内提出，且只能以个人名义提出，不得以原告或集体成员身份参与任何集体诉讼、共同诉讼或代表人诉讼。",
        ]),
        Section(heading: "18. 条款变更", paragraphs: [
            "我们可能不时更新本条款，页首日期即最新版本日期。如属重大变更，我们会在生效前在 App 内告知你。变更生效后你继续使用本服务，即表示你接受更新后的条款；如不接受，请停止使用本服务并注销账户。",
        ]),
        Section(heading: "19. 其他", paragraphs: [
            "本条款与《隐私政策》构成你与我们之间就本服务达成的完整协议。任何条款被认定为无法执行的，应在可能的最大范围内执行，其余条款继续有效。我们未行使某项权利，不构成对该权利的放弃。你不得转让本条款；在合并、收购或资产出售时，我们可以转让本条款。因超出我们合理控制范围的事件造成的延误或未能履行，我们不承担责任。本条款的中文版与英文版如有冲突，以英文版为准，法律另有规定的除外。",
        ]),
        Section(heading: "20. 关于 Apple", paragraphs: [
            "本条款仅在你与 NextBody 之间订立，不涉及 Apple。Apple 不对 App 及其内容负责，也没有义务为其提供维护或支持。如 App 不符合任何适用的保证，你可以通知 Apple，Apple 将退还 App 的购买价格（如有）；在法律允许的最大范围内，Apple 对 App 不承担其他任何保证义务。",
            "Apple 不负责处理与 App 相关的任何索赔，包括产品责任索赔、App 不符合法律或监管要求的索赔、消费者保护或隐私方面的索赔，以及 App 侵犯第三方知识产权的索赔。你确认你不位于受美国政府禁运或被认定为支持恐怖主义的国家，也不在美国政府的任何禁止或限制交易方名单上。Apple 及其子公司是本条款的第三方受益人，有权对你执行本条款。",
        ]),
        Section(heading: "21. 联系我们", paragraphs: [
            "关于本条款的问题：shop@nextbody.ai。关于你的数据的问题：privacy@nextbody.ai。",
        ]),
    ]

    // MARK: - Privacy Policy · English

    static let privacyEN: [Section] = [
        Section(heading: "1. Who we are", paragraphs: [
            "This Privacy Policy explains how NextBody (\"we\", \"us\") collects, uses, shares and protects personal information when you use the NextBody app, your account, NextBody Pro and a paired HOOP band. NextBody is the controller of that information. It also serves as our consumer health data privacy notice. Questions: privacy@nextbody.ai.",
            "Before the app reads any health data, it shows you a separate consent screen listing exactly what it collects. You can change that decision at any time in Profile › Data & Legal › Collecting health data.",
        ]),
        Section(heading: "2. What we collect", paragraphs: [
            "Account: your email address, your name if you provide it, and the identifier issued by Sign in with Apple or Google. If you use Apple's Hide My Email, we see only the relay address.",
            "Profile: sex, date of birth, height and weight, entered by you or read from Apple Health with your permission, plus your goal, units, language and settings. We only read from Apple Health; we never write to it.",
            "Band readings, only after you consent: heart rate, heart rate variability including raw beat-to-beat intervals, steps, distance, calories and movement intensity, sleep signals (staging, duration, night HRV and overnight automatic blood oxygen), skin temperature, wrist optical meal response, and the body composition scans you start yourself. From these we compute scores such as sleep score, Body Battery, training load and energy targets.",
            "What the band can do but we never switch on: blood pressure, ECG, and daytime or on-demand blood oxygen. We do not enable, store or show them.",
            "Meals: the words, voice and photos you use to log food, and the estimates made from them. Location metadata is removed from photos on upload.",
            "Voice: when you speak to the app, the audio is streamed to a speech recognition provider to turn it into text. We do not store the recording; we keep the resulting text as part of the conversation or meal.",
            "AI conversations: your messages, the AI's replies, the plans and screens it produces, and facts it remembers about you to personalise later answers, such as preferences or injuries you mention.",
            "Phone motion: step counts from your iPhone's motion sensors, used when the band is out of range, if you allow it.",
            "Subscription: whether you have NextBody Pro, the product, and its renewal and expiry dates, from Apple via RevenueCat. We never receive your payment card details.",
            "Device and usage: phone model, operating system and app version, band model, firmware version and battery level, a Bluetooth identifier for each paired band, which screens you open, what fails, timings and error reports.",
            "Support: what you send through Report a problem or by email, including screenshots and the app state attached to the report.",
            "Consent records: each consent decision, the version and a fingerprint of the text you saw, the time and the language.",
            "We do not collect your precise location, contacts, or the advertising identifier, and we do not track you across other companies' apps or websites.",
        ]),
        Section(heading: "3. How we use it", paragraphs: [
            "To provide the Service: sync and store your readings, compute your day, show your history, estimate meals, and run the AI features you use.",
            "To run subscriptions and daily AI allowances, keep the Service secure, prevent abuse and fraud, and enforce our Terms.",
            "To support you, fix bugs and improve reliability and features, using usage data and error reports.",
            "To comply with law, respond to lawful requests, and establish or defend legal claims.",
            "We may create aggregated or de-identified information that can no longer reasonably identify you, and use it for any lawful purpose.",
            "We do not sell your personal information, do not use your health data for advertising, do not share it with data brokers, and do not use it to make decisions with legal or similarly significant effects about you.",
        ]),
        Section(heading: "4. Legal bases", paragraphs: [
            "Where the GDPR, UK GDPR, China's Personal Information Protection Law or similar laws apply, we rely on: your explicit, separate consent for health and other sensitive personal information; the performance of our contract with you to run your account and subscription; our legitimate interests in securing, fixing and improving the Service, which we balance against your rights; and legal obligations.",
            "Where processing is based on consent, you can withdraw it at any time. Withdrawal does not affect processing that already took place.",
        ]),
        Section(heading: "5. Who we share it with", paragraphs: [
            "We share personal information only with service providers that process it on our behalf to run the Service, under their terms and data processing commitments:",
            "Supabase: hosting, database, sign-in and file storage, on Amazon Web Services servers in the United States (US West).",
            "AI model providers: xAI (Grok), our primary model, and Alibaba Cloud Model Studio (Qwen), used as a fallback model and for speech recognition and web search. When you use an AI feature, the text of your request, relevant readings, meal photos or audio are sent to them to produce the result. These providers may keep inputs for a limited time under their own terms, for example for abuse monitoring. Web search queries are also passed to the search engines those providers use.",
            "TypeSafe (Jev): when enabled for an AI feature, relevant request text and application context are sent to TypeSafe to select actions or interpret requests. This decision service is separate from the model that writes the answer.",
            "RevenueCat: purchase and subscription status, linked to your NextBody account identifier so access can be restored across your devices. This identifier is pseudonymous, not anonymous.",
            "Apple and Google: when you sign in with them, and Apple for App Store purchases and Apple Health.",
            "GitHub: problem reports you send are filed in our private issue tracker; attached screenshots are stored under an unlisted link.",
            "The HOOP band's software kit runs inside the app on your phone to talk to the band over Bluetooth.",
            "We may also disclose information when required by law or legal process, to protect the rights, property or safety of our users, the public or us, in connection with a merger, acquisition, financing or sale of assets (subject to this Policy), or with your direction or consent.",
        ]),
        Section(heading: "6. International transfers", paragraphs: [
            "We and our providers process information in the United States, mainland China and other countries whose data protection laws may differ from yours. When you use AI features, your request may be processed in both the United States and mainland China. By using the Service and giving the consents described here, you acknowledge these transfers. Where the law requires, we rely on appropriate safeguards such as standard contractual clauses, and on your separate consent.",
        ]),
        Section(heading: "7. How long we keep it", paragraphs: [
            "Account, profile, readings, meals, AI conversations and remembered facts: for as long as your account exists, unless you delete them earlier.",
            "Our configured retention targets are 30 days for meal photos, 90 days for AI screen outputs, 180 days for usage analytics, and 400 days for raw overnight oxygen and meal response samples. Removal depends on the relevant cleanup job being deployed and running; these targets are not a guarantee that every copy is erased on that day. We do not store voice recordings in NextBody storage. Contact us to request deletion independently of scheduled cleanup.",
            "When account deletion completes successfully, your account access is revoked and the associated app data is deleted from our live systems. Copies may remain in backups until the hosting provider's backup retention period expires. Support reports in GitHub, their attached screenshots and provider-held records are not automatically erased by the in-app account deletion; contact us to request their deletion, subject to applicable retention obligations. We may keep consent records, subscription records and anything needed to meet legal obligations, resolve disputes, or enforce our agreements, for as long as that requires.",
        ]),
        Section(heading: "8. Your rights and choices", paragraphs: [
            "In the app you can: correct your profile; delete meals and entries; see and erase what the AI remembers in Profile › AI memory; withdraw health data consent in Profile › Collecting health data, which stops collection; and delete your account and its data in Profile › Delete account. In iOS Settings you can turn off Apple Health, camera, microphone, photos, motion, Bluetooth and notification access at any time; some features will then stop working.",
            "Depending on where you live, you may also have the right to access or get a copy of your information, to have it corrected or deleted, to restrict or object to processing, to data portability, to withdraw consent, and to not be discriminated against for exercising these rights. Residents of Washington, Nevada and other US states with consumer health data laws have the right to know which third parties receive their consumer health data.",
            "To make a request, write to privacy@nextbody.ai from the email on your account. We may need to verify your identity before acting. We reply within 30 days, or the shorter period your law requires. If we decline your request, you can appeal by replying to our answer. You also have the right to complain to your local data protection authority.",
        ]),
        Section(heading: "9. Security", paragraphs: [
            "We use reasonable technical and organisational measures to protect your information, including encryption in transit, access controls that keep each account's data to that account, and limited staff access. No system is completely secure, and we cannot guarantee the security of information sent over the internet or stored on your devices. Keep your phone locked and your sign-in methods safe.",
            "If a breach affects your personal information, we will notify you and the authorities as the law requires.",
        ]),
        Section(heading: "10. Children and teenagers", paragraphs: [
            "The Service is not directed to children under 16. You must also meet any higher age required to independently consent to the processing of your data where you live. We do not currently offer a verified parental-consent process for children below that age. If you believe we have collected data from someone who does not meet these requirements, contact privacy@nextbody.ai so we can investigate and delete the affected account and data as required.",
        ]),
        Section(heading: "11. Changes", paragraphs: [
            "We may update this Policy. The date at the top shows the latest version. If we make a material change, such as a new kind of data, a new purpose or a new category of provider, we will tell you in the app before it takes effect, and ask for your consent again where the law requires.",
        ]),
        Section(heading: "12. Contact", paragraphs: [
            "Privacy questions and requests: privacy@nextbody.ai.",
        ]),
    ]

    // MARK: - Privacy Policy · 中文

    static let privacyZH: [Section] = [
        Section(heading: "1. 我们是谁", paragraphs: [
            "本《隐私政策》说明你使用 NextBody App、你的账户、NextBody Pro 以及已配对的 HOOP 手环时，NextBody（「我们」）如何收集、使用、共享和保护你的个人信息。NextBody 是这些信息的处理者（控制者）。本政策同时作为我们的消费者健康数据隐私声明。如有问题，请写信至 privacy@nextbody.ai。",
            "在 App 读取任何健康数据之前，会先向你展示一个单独的同意页面，完整列出将收集的内容。你可以随时在「个人资料 › 数据与法律 › 正在采集健康数据」中更改这一决定。",
        ]),
        Section(heading: "2. 我们收集什么", paragraphs: [
            "账户信息：你的邮箱地址、你提供的姓名，以及通过 Apple 或 Google 登录时对方分配的标识符。如你使用 Apple 的「隐藏邮件地址」，我们只能看到中转地址。",
            "个人资料：性别、出生日期、身高和体重，由你填写，或经你授权从 Apple 健康读取；以及你的目标、单位、语言和各项设置。我们只从 Apple 健康读取，从不写入。",
            "手环读数（仅在你同意后）：心率、心率变异性（含原始逐拍间期）、步数、距离、热量和活动强度、睡眠信号（分期、时长、夜间 HRV 和夜间自动血氧）、皮肤温度、腕部光学餐后反应，以及由你亲自发起的身体成分测量。我们据此计算睡眠评分、身体电量、训练负荷和能量目标等指标。",
            "手环具备但我们从不开启的功能：血压、心电图，以及白天或手动触发的血氧测量。我们不开启、不存储、也不显示这些数据。",
            "餐食：你用来记录饮食的文字、语音和照片，以及据此得出的估算结果。照片上传时会去除位置信息。",
            "语音：你对 App 说话时，音频会实时传给语音识别服务商转成文字。我们不保存录音，只保留转写后的文字，作为对话或餐食记录的一部分。",
            "AI 对话：你发送的消息、AI 的回复、AI 生成的计划和页面，以及 AI 为让之后的回答更贴合你而记住的信息（例如你提到的偏好或伤病）。",
            "手机运动数据：经你允许，在手环不在身边时使用 iPhone 运动传感器统计的步数。",
            "订阅信息：你是否拥有 NextBody Pro、订阅的产品及续期和到期时间，由 Apple 经 RevenueCat 提供给我们。我们从不接触你的银行卡信息。",
            "设备与使用信息：手机型号、操作系统和 App 版本，手环型号、固件版本和电量，每个已配对手环的蓝牙标识符，你打开了哪些页面、哪里出错、耗时和错误报告。",
            "支持信息：你通过「反馈问题」或邮件发送的内容，包括截图和随报告附带的 App 状态信息。",
            "同意记录：你每一次的同意决定、你所看到文本的版本和指纹、时间和语言。",
            "我们不收集你的精确位置、通讯录或广告标识符，也不在其他公司的 App 或网站上追踪你。",
        ]),
        Section(heading: "3. 我们如何使用", paragraphs: [
            "提供本服务：同步和保存读数、计算你的一天、展示历史记录、估算餐食，以及运行你所使用的 AI 功能。",
            "管理订阅和每日 AI 额度，保障本服务安全，防范滥用和欺诈，执行我们的条款。",
            "利用使用数据和错误报告为你提供支持、修复缺陷、改进稳定性和功能。",
            "遵守法律，回应合法要求，以及确立或抗辩法律主张。",
            "我们可能生成汇总或去标识化后无法再合理识别到你的信息，并将其用于任何合法目的。",
            "我们不出售你的个人信息，不将你的健康数据用于广告，不与数据经纪商共享，也不利用它对你作出具有法律效力或类似重大影响的决定。",
        ]),
        Section(heading: "4. 处理依据", paragraphs: [
            "在适用 GDPR、英国 GDPR、中国《个人信息保护法》或类似法律的情况下，我们的处理依据是：就健康信息及其他敏感个人信息取得你的明示单独同意；为履行与你之间的合同而运行你的账户和订阅；为保障、修复和改进本服务的正当利益（我们会与你的权利进行权衡）；以及履行法定义务。",
            "基于同意的处理，你可以随时撤回同意。撤回不影响撤回前已进行的处理。",
        ]),
        Section(heading: "5. 我们与谁共享", paragraphs: [
            "我们只与代表我们处理信息、以运行本服务的服务商共享个人信息，并受其条款和数据处理承诺约束：",
            "Supabase：托管、数据库、登录和文件存储，服务器位于美国（美国西部）的亚马逊云服务（AWS）上。",
            "AI 模型服务商：主要模型 xAI（Grok），以及阿里云百炼（通义千问），后者用作备用模型并提供语音识别和网络搜索。你使用 AI 功能时，请求内容、相关读数、餐食照片或音频会发送给这些服务商以生成结果。服务商可能按其自身条款在有限时间内保留输入内容，例如用于滥用监测。网络搜索的查询内容也会传给这些服务商所使用的搜索引擎。",
            "TypeSafe（Jev）：在 AI 功能启用此服务时，相关请求文字及应用上下文会发送给 TypeSafe，用于选择操作或理解请求。它与撰写回答的模型是不同的服务。",
            "RevenueCat：购买与订阅状态，关联到你的 NextBody 账户标识符，以便在你的设备间恢复使用权限。该标识符是假名化标识，而非不可识别的匿名数据。",
            "Apple 和 Google：当你通过它们登录时；以及 Apple 用于 App Store 购买和 Apple 健康。",
            "GitHub：你提交的问题反馈会记录在我们的私有问题跟踪系统中；附带的截图存储在不公开列出的链接下。",
            "HOOP 手环的软件开发包在你手机上的 App 内运行，用于通过蓝牙与手环通信。",
            "此外，在法律或法律程序要求时，为保护用户、公众或我们的权利、财产或安全时，在合并、收购、融资或资产出售时（仍受本政策约束），或经你指示或同意时，我们也可能披露信息。",
        ]),
        Section(heading: "6. 跨境传输", paragraphs: [
            "我们和我们的服务商会在美国、中国大陆及其他国家或地区处理信息，这些地方的数据保护法律可能与你所在地不同。你使用 AI 功能时，你的请求可能同时在美国和中国大陆被处理。你使用本服务并作出本政策所述的同意，即表示你知悉这些传输。在法律要求的情况下，我们会采用标准合同条款等适当保障措施，并取得你的单独同意。",
        ]),
        Section(heading: "7. 保留多久", paragraphs: [
            "账户、个人资料、读数、餐食、AI 对话和 AI 记住的信息：在你的账户存续期间保留，除非你提前删除。",
            "我们配置的保留目标为：餐食照片 30 天，AI 生成的页面 90 天，使用分析数据 180 天，夜间血氧和餐后反应的原始采样 400 天。删除依赖相应清理任务完成部署并正常运行，上述目标不保证每个副本均在当日清除。NextBody 存储中不保存语音录音。你可以联系我们申请删除，无需等待定期清理。",
            "账户注销成功完成后，账户访问权限会被撤销，相关 App 数据会从我们的在线系统中删除。备份副本可能保留至托管服务商的备份保留期届满。GitHub 中的问题反馈、附带截图及服务商持有的记录不会随 App 内注销操作自动清除；你可以联系我们申请删除，但适用的法定保留义务除外。为履行法定义务、解决争议或执行协议所需的同意记录、订阅记录及其他信息，我们可能在所需期限内保留。",
        ]),
        Section(heading: "8. 你的权利与选择", paragraphs: [
            "在 App 内，你可以：更正个人资料；删除餐食和记录；在「个人资料 › AI 记忆」中查看并清除 AI 记住的内容；在「个人资料 › 正在采集健康数据」中撤回健康数据同意，停止收集；在「个人资料 › 删除账户」中注销账户并删除数据。在 iOS 设置中，你可以随时关闭 Apple 健康、相机、麦克风、照片、运动、蓝牙和通知权限；关闭后部分功能将无法使用。",
            "根据你所在地的法律，你还可能享有以下权利：查阅或获取你的信息副本，更正或删除信息，限制或反对处理，数据可携带，撤回同意，以及不因行使上述权利而受到歧视。华盛顿州、内华达州及其他制定了消费者健康数据法律的美国州的居民，有权知道哪些第三方接收了其消费者健康数据。",
            "如需提出请求，请使用账户邮箱写信至 privacy@nextbody.ai。我们可能需要先核实你的身份。我们会在 30 天内答复，或在你所在地法律规定的更短期限内答复。如我们拒绝你的请求，你可以直接回复我们的答复提出申诉。你也有权向当地数据保护监管机构投诉。",
        ]),
        Section(heading: "9. 安全", paragraphs: [
            "我们采取合理的技术和管理措施保护你的信息，包括传输加密、确保每个账户的数据只能由该账户访问的访问控制，以及严格限制员工访问。没有任何系统是绝对安全的，我们无法保证通过互联网传输或存储在你设备上的信息的安全。请锁好你的手机，妥善保管登录方式。",
            "如发生影响你个人信息的安全事件，我们将按法律要求通知你和有关部门。",
        ]),
        Section(heading: "10. 儿童与青少年", paragraphs: [
            "本服务不面向未满 16 周岁的儿童。你还必须满足所在地法律对独立同意处理个人信息规定的更高年龄要求。我们目前不提供针对低于该年龄儿童的可验证监护人同意流程。如你认为我们收集了不符合上述条件者的信息，请联系 privacy@nextbody.ai，我们将核查并按要求删除相关账户和数据。",
        ]),
        Section(heading: "11. 政策变更", paragraphs: [
            "我们可能更新本政策，页首日期即最新版本日期。如有重大变更（例如新增数据类型、新增用途或新增服务商类别），我们会在生效前在 App 内告知你，并在法律要求时重新征得你的同意。",
        ]),
        Section(heading: "12. 联系我们", paragraphs: [
            "隐私问题和请求：privacy@nextbody.ai。",
        ]),
    ]
}
