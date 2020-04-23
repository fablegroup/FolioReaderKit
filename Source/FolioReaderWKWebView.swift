//
//  FolioReaderWKWebView.swift
//  FolioReaderKit
//
//  Created by Laurence Andersen on 4/7/20.
//

import UIKit
import WebKit
import MenuItemKit


class FolioReaderWKWebView: WKWebView {
    struct ContentDimensions {
        let contentWidth: CGFloat
        let contentHeight: CGFloat
        let viewportWidth: CGFloat
        let viewportHeight: CGFloat
        let scrollLeft: CGFloat
        let scrollTop: CGFloat
        
        func pageExtentUsingConfiguration(_ configuration: FolioReaderConfig) -> CGFloat {
            return configuration.isDirection(viewportHeight, viewportWidth, viewportHeight)
        }
        
        func totalContentExtentUsingConfiguation(_ configuration: FolioReaderConfig) -> CGFloat {
            return configuration.isDirection(contentHeight, contentWidth, contentHeight)
        }
        
        func pageCountUsingConfiguration(_ configuration: FolioReaderConfig) -> Int {
            let pageExtent = pageExtentUsingConfiguration(configuration)
            let totalContentExtent = totalContentExtentUsingConfiguation(configuration)
            
            guard pageExtent > 0 && totalContentExtent > 0 else {
                return 0
            }
            
            let totalPages = Int(ceil(totalContentExtent) / pageExtent)
            return totalPages
        }
        
        func pageNumberForOffset(_ offset: CGFloat, usingConfiguration configuration: FolioReaderConfig) -> Int {
            let pageExtent = pageExtentUsingConfiguration(configuration)
            let totalContentExtent = totalContentExtentUsingConfiguation(configuration)
            
            guard pageExtent > 0 && totalContentExtent > 0 else {
                return 0
            }
            
            guard offset > pageExtent else {
                return 1
            }
            
            let p = Int(ceil((totalContentExtent / pageExtent) * (offset / totalContentExtent))) + 1
            return p
        }
        
        func offsetForPageNumber(_ pageNumber: Int, usingConfiguration configuration: FolioReaderConfig) -> CGPoint {
            let pageExtent = pageExtentUsingConfiguration(configuration)
            let totalContentExtent = totalContentExtentUsingConfiguation(configuration)
            
            let offset = (CGFloat(pageNumber) - 1) * pageExtent
            
            return configuration.isDirection(CGPoint(x: 0.0, y: offset), CGPoint(x: offset, y: 0.0), CGPoint(x: 0.0, y: offset))
        }
        
        func offsetForLastPage(usingConfiguration configuration: FolioReaderConfig) -> CGPoint {
            let lastPageNumber = pageCountUsingConfiguration(configuration)
            return offsetForPageNumber(lastPageNumber, usingConfiguration: configuration)
        }
    }
    
    var isColors = false
    var isShare = false
    var isOneWord = false
    
    var menuIsVisible = false
    
    var pageCount: Int {
        get {
            return 2
        }
    }
    
    fileprivate weak var readerContainer: FolioReaderContainer?
    fileprivate var contentController: WKUserContentController?

    fileprivate var readerConfig: FolioReaderConfig {
        guard let readerContainer = readerContainer else { return FolioReaderConfig() }
        return readerContainer.readerConfig
    }

    fileprivate var book: FRBook {
        guard let readerContainer = readerContainer else { return FRBook() }
        return readerContainer.book
    }

    fileprivate var folioReader: FolioReader {
        guard let readerContainer = readerContainer else { return FolioReader() }
        return readerContainer.folioReader
    }
    
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        fatalError("use init(frame:readerConfig:book:) instead.")
    }

    init(frame: CGRect, readerContainer: FolioReaderContainer) {
        let configuration = WKWebViewConfiguration()
        if #available(iOS 10.0, *) {
            configuration.dataDetectorTypes = .link
            //configuration.ignoresViewportScaleLimits = false
        }
        
        if #available(iOS 13.0, *) {
            let preferences = WKWebpagePreferences()
            preferences.preferredContentMode = .mobile
            configuration.defaultWebpagePreferences = preferences
        }
        
        contentController = WKUserContentController()
        configuration.userContentController = contentController!
        
        if let dimensionJSFilePath = Bundle.frameworkBundle().path(forResource: "Dimensions", ofType: "js") {
            do {
                let scriptSource = try String(contentsOfFile: dimensionJSFilePath, encoding: .utf8)
                let dimensionsScript = WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
                
                contentController!.addUserScript(dimensionsScript)
            } catch {
                print("Error injecting Folio Reader JavaScript: \(error)")
            }
        }
        
        super.init(frame: frame, configuration: configuration)
        
        self.scrollView.isPagingEnabled = true
        self.readerContainer = readerContainer
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UIMenuController

    open override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard readerConfig.useReaderMenuController else {
            return super.canPerformAction(action, withSender: sender)
        }

        if isShare {
            return false
        } else if isColors {
            return false
        } else {
            if action == #selector(highlight(_:))
                || action == #selector(highlightWithNote(_:))
                || action == #selector(updateHighlightNote(_:))
                || (action == #selector(colors(_:)))
                || (action == #selector(remove(_:)))
                || (action == #selector(define(_:)) && isOneWord)
                || (action == #selector(play(_:)) && (book.hasAudio || readerConfig.enableTTS))
                || (action == #selector(share(_:)) && readerConfig.allowSharing)
                || (action == #selector(copy(_:)) && readerConfig.allowSharing) {
                return true
            }
            return false
        }
    }
    
    // MARK: - UIMenuController - Actions

    @objc func share(_ sender: UIMenuController) {
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        let shareImage = UIAlertAction(title: self.readerConfig.localizedShareImageQuote, style: .default, handler: { (action) -> Void in
            if self.isShare {
                self.js("getHighlightContent()") { textToShare in
                    guard let textToShare = textToShare as? String else {
                        return
                    }
                    
                    self.folioReader.readerCenter?.presentQuoteShare(textToShare)
                }
            } else {
                self.js("getSelectedText()") { textToShare in
                    guard let textToShare = textToShare as? String else {
                        return
                    }
                    
                    self.folioReader.readerCenter?.presentQuoteShare(textToShare)

                    self.clearTextSelection()
                }
            }
            
            self.setMenuVisible(false)
        })

        let shareText = UIAlertAction(title: self.readerConfig.localizedShareTextQuote, style: .default) { (action) -> Void in
            if self.isShare {
                self.js("getHighlightContent()") { textToShare in
                    guard let textToShare = textToShare as? String else {
                        return
                    }
                    
                    self.folioReader.readerCenter?.shareHighlight(textToShare, rect: sender.menuFrame)
                }
            } else {
                self.js("getSelectedText()") { textToShare in
                   guard let textToShare = textToShare as? String else {
                       return
                   }
                       
                    self.folioReader.readerCenter?.shareHighlight(textToShare, rect: sender.menuFrame)
                }
            }
            
            self.setMenuVisible(false)
        }

        let cancel = UIAlertAction(title: self.readerConfig.localizedCancel, style: .cancel, handler: nil)

        alertController.addAction(shareImage)
        alertController.addAction(shareText)
        alertController.addAction(cancel)

        if let alert = alertController.popoverPresentationController {
            alert.sourceView = self.folioReader.readerCenter?.currentPage
            alert.sourceRect = sender.menuFrame
        }

        self.folioReader.readerCenter?.present(alertController, animated: true, completion: nil)
    }

    @objc func colors(_ sender: UIMenuController?) {
        isColors = true
        createMenu(options: false)
        setMenuVisible(true)
    }

    @objc func remove(_ sender: UIMenuController?) {
        js("removeThisHighlight()") { removedId in
            guard let removedId = removedId as? String else {
                return
            }
            
            Highlight.removeById(withConfiguration: self.readerConfig, highlightId: removedId)
        }
        
        self.setMenuVisible(false)
    }

    @objc func highlight(_ sender: UIMenuController?) {
        js("highlightString('\(HighlightStyle.classForStyle(self.folioReader.currentHighlightStyle))')") { highlightAndReturn in
            let jsonData = (highlightAndReturn as? String)?.data(using: String.Encoding.utf8)

            do {
                let json = try JSONSerialization.jsonObject(with: jsonData!, options: []) as! NSArray
                let dic = json.firstObject as! [String: String]
                let rect = NSCoder.cgRect(for: dic["rect"]!)
                
                guard let startOffset = dic["startOffset"] else {
                    return
                }
                
                guard let endOffset = dic["endOffset"] else {
                    return
                }

                self.createMenu(options: true)
                self.setMenuVisible(true, andRect: rect)

                self.js("getHTML()") { html in
                    guard let html = html as? String, let identifier = dic["id"], let bookId = (self.book.name as NSString?)?.deletingPathExtension else {
                        return
                    }
                    
                    let pageNumber = self.folioReader.readerCenter?.currentPageNumber ?? 0
                    let match = Highlight.MatchingHighlight(text: html, id: identifier, startOffset: startOffset, endOffset: endOffset, bookId: bookId, currentPage: pageNumber)
                    let highlight = Highlight.matchHighlight(match)
                    highlight?.persist(withConfiguration: self.readerConfig)
                }
            } catch {
                print("Could not receive JSON")
            }
        }
    }
    
    @objc func highlightWithNote(_ sender: UIMenuController?) {
        js("highlightStringWithNote('\(HighlightStyle.classForStyle(self.folioReader.currentHighlightStyle))')") { highlightAndReturn in
            let jsonData = (highlightAndReturn as? String)?.data(using: String.Encoding.utf8)
            
            do {
                let json = try JSONSerialization.jsonObject(with: jsonData!, options: []) as! NSArray
                let dic = json.firstObject as! [String: String]
                guard let startOffset = dic["startOffset"] else { return }
                guard let endOffset = dic["endOffset"] else { return }
                
                self.clearTextSelection()
                
                self.js("getHTML()") { html in
                    guard let html = html as? String, let identifier = dic["id"], let bookId = (self.book.name as NSString?)?.deletingPathExtension else {
                        return
                    }
                    
                    let pageNumber = self.folioReader.readerCenter?.currentPageNumber ?? 0
                    let match = Highlight.MatchingHighlight(text: html, id: identifier, startOffset: startOffset, endOffset: endOffset, bookId: bookId, currentPage: pageNumber)
                    if let highlight = Highlight.matchHighlight(match) {
                        self.folioReader.readerCenter?.presentAddHighlightNote(highlight, edit: false)
                    }
                }
            } catch {
                print("Could not receive JSON")
            }
        }
    }
    
    @objc func shareHighlight(_ sender: UIMenuController?) {
        
    }
    
    @objc func updateHighlightNote (_ sender: UIMenuController?) {
        js("getHighlightId()") { highlightId in
            guard let highlightId = highlightId as? String, let highlightNote = Highlight.getById(withConfiguration: self.readerConfig, highlightId: highlightId) else {
                return
            }
            
            self.folioReader.readerCenter?.presentAddHighlightNote(highlightNote, edit: true)
        }
    }

    @objc func define(_ sender: UIMenuController?) {
        js("getSelectedText()") { selectedText in
            guard let selectedText = selectedText as? String, let readerContainer = self.readerContainer else {
                return
            }
            
            self.setMenuVisible(false)
            self.clearTextSelection()

            let vc = UIReferenceLibraryViewController(term: selectedText)
            vc.view.tintColor = self.readerConfig.tintColor
            readerContainer.show(vc, sender: nil)
        }
    }

    @objc func play(_ sender: UIMenuController?) {
        self.folioReader.readerAudioPlayer?.play()

        self.clearTextSelection()
    }

    func setYellow(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .yellow)
    }

    func setGreen(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .green)
    }

    func setBlue(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .blue)
    }

    func setPink(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .pink)
    }

    func setUnderline(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .underline)
    }

    func changeHighlightStyle(_ sender: UIMenuController?, style: HighlightStyle) {
        self.folioReader.currentHighlightStyle = style.rawValue
        
        js("setHighlightStyle('\(HighlightStyle.classForStyle(style.rawValue))')") { updateId in
            guard let updateId = updateId as? String else {
                return
            }
            
            Highlight.updateById(withConfiguration: self.readerConfig, highlightId: updateId, type: style)
        }
        
        //FIX: https://github.com/FolioReader/FolioReaderKit/issues/316
        setMenuVisible(false)
    }

    // MARK: - Create and show menu

    func createMenu(options: Bool) {
        guard (self.readerConfig.useReaderMenuController == true) else {
            return
        }

        isShare = options

        let colors = UIImage(readerImageNamed: "colors-marker")
        let share = UIImage(readerImageNamed: "share-marker")
        let remove = UIImage(readerImageNamed: "no-marker")
        let yellow = UIImage(readerImageNamed: "yellow-marker")
        let green = UIImage(readerImageNamed: "green-marker")
        let blue = UIImage(readerImageNamed: "blue-marker")
        let pink = UIImage(readerImageNamed: "pink-marker")
        let underline = UIImage(readerImageNamed: "underline-marker")

        let menuController = UIMenuController.shared

        let highlightItem = UIMenuItem(title: self.readerConfig.localizedHighlightMenu, action: #selector(highlight(_:)))
        let highlightNoteItem = UIMenuItem(title: self.readerConfig.localizedHighlightNote, action: #selector(highlightWithNote(_:)))
        let editNoteItem = UIMenuItem(title: self.readerConfig.localizedHighlightNote, action: #selector(updateHighlightNote(_:)))
        let playAudioItem = UIMenuItem(title: self.readerConfig.localizedPlayMenu, action: #selector(play(_:)))
        let defineItem = UIMenuItem(title: self.readerConfig.localizedDefineMenu, action: #selector(define(_:)))

        // TODO: Move this out of FolioReader - Buzz
        let shareHighlightItem = UIMenuItem(title: "Share to Chat", action: #selector(shareHighlight(_:)))

        // TODO: Figure out a way to make these images again without relying on MenuItemKit
        let colorsItem = UIMenuItem(title: NSLocalizedString("Set Color", comment: ""), action: #selector(colors(_:)))
        let shareItem = UIMenuItem(title: NSLocalizedString("Share", comment: ""), action: #selector(share(_:)))
        let removeItem = UIMenuItem(title: NSLocalizedString("Remove", comment: ""), action: #selector(remove(_:)))

        // TODO: Come up with a way to do this that doesn't rely on MenuItemKit
        let yellowItem = UIMenuItem(title: "Y", image: yellow) { [weak self] _ in
            self?.setYellow(menuController)
        }
        let greenItem = UIMenuItem(title: "G", image: green) { [weak self] _ in
            self?.setGreen(menuController)
        }
        let blueItem = UIMenuItem(title: "B", image: blue) { [weak self] _ in
            self?.setBlue(menuController)
        }
        let pinkItem = UIMenuItem(title: "P", image: pink) { [weak self] _ in
            self?.setPink(menuController)
        }
        let underlineItem = UIMenuItem(title: "U", image: underline) { [weak self] _ in
            self?.setUnderline(menuController)
        }

        var menuItems: [UIMenuItem] = []

        // menu on existing highlight
        if isShare {
            menuItems = [colorsItem, editNoteItem, removeItem, shareHighlightItem]
            
            if (self.readerConfig.allowSharing == true) {
                menuItems.append(shareItem)
            }
            
            isShare = false
        } else if isColors {
            // menu for selecting highlight color
            menuItems = [yellowItem, greenItem, blueItem, pinkItem, underlineItem]
        } else {
            // default menu
            menuItems = [highlightItem, defineItem, highlightNoteItem]

            if self.book.hasAudio || self.readerConfig.enableTTS {
                menuItems.insert(playAudioItem, at: 0)
            }

            if (self.readerConfig.allowSharing == true) {
                menuItems.append(shareItem)
            }
        }
        
        menuController.menuItems = menuItems
    }
    
    open func setMenuVisible(_ menuVisible: Bool, animated: Bool = true, andRect rect: CGRect = CGRect.zero) {
        if !menuVisible && isShare || !menuVisible && isColors {
            isColors = false
            isShare = false
        }
        
        if menuVisible  {
            if !rect.equalTo(CGRect.zero) {
                UIMenuController.shared.setTargetRect(rect, in: self)
            }
        }
        
        menuIsVisible = menuVisible
        
        UIMenuController.shared.setMenuVisible(menuVisible, animated: animated)
    }
    
    // MARK: - Content Size/Dimensions
    
    func getContentDimensions(completion: @escaping (ContentDimensions?) -> Void) {
        evaluateJavaScript("document.readyState") { (result, error) in
            guard let result = result else {
                completion(nil)
                return
            }
            
            self.evaluateJavaScript("getContentDimensions()") { (result, error) in
                guard let resultJSON = result as? [String : Any], let scrollHeight = resultJSON["scrollHeight"] as? Int, let scrollWidth = resultJSON["scrollWidth"] as? Int, let scrollLeft = resultJSON["scrollLeft"] as? Int, let scrollTop = resultJSON["scrollTop"] as? Int, let viewportWidth = resultJSON["viewportWidth"] as? Int, let viewportHeight = resultJSON["viewportHeight"] as? Int else {
                    completion(nil)
                    return
                }
                
                let dimensions = ContentDimensions(contentWidth: CGFloat(scrollWidth), contentHeight: CGFloat(scrollHeight), viewportWidth: CGFloat(viewportWidth), viewportHeight: CGFloat(viewportHeight), scrollLeft: CGFloat(scrollLeft), scrollTop: CGFloat(scrollTop))
                
                completion(dimensions)
            }
        }
    }
    
    func scrollPageToPoint(_ point: CGPoint, completion: ((Error?) -> Void)? = nil) {
        evaluateJavaScript("document.readyState") { (result, error) in
            guard let result = result else {
                completion?(error)
                return
            }
            
            let script = "scrollTo(\(point.x), \(point.y))"
            
            self.evaluateJavaScript(script) { (result, error) in
                guard let result = result else {
                    completion?(error)
                    return
                }
                
                completion?(nil)
            }
        }
    }
    
    // MARK: - JavaScript Bridge
    
    open func js(_ script: String, completion: ((Any?) -> Void)? = nil) {
        evaluateJavaScript(script) { (result, error) in
            guard let c = completion else {
                return
            }
            
            c(result)
        }

    }
    
    // MARK: WebView
    
    func clearTextSelection() {
        // Forces text selection clearing
        // @NOTE: this doesn't seem to always work
        
        self.isUserInteractionEnabled = false
        self.isUserInteractionEnabled = true
    }
    
    func setupScrollDirection() {
        switch self.readerConfig.scrollDirection {
        case .vertical, .defaultVertical, .horizontalWithVerticalContent:
            scrollView.isPagingEnabled = false
            scrollView.bounces = true
            break
        case .horizontal:
            scrollView.isPagingEnabled = true
            scrollView.bounces = false
            break
        }
    }
    
}
