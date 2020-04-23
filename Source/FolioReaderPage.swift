//
//  FolioReaderPage.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 10/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import SafariServices
import WebKit

/// Protocol which is used from `FolioReaderPage`s.
@objc public protocol FolioReaderPageDelegate: class {

    /**
     Notify that the page will be loaded. Note: The webview content itself is already loaded at this moment. But some java script operations like the adding of class based on click listeners will happen right after this method. If you want to perform custom java script before this happens this method is the right choice. If you want to modify the html content (and not run java script) you have to use `htmlContentForPage()` from the `FolioReaderCenterDelegate`.

     - parameter page: The loaded page
     */
    @objc optional func pageWillLoad(_ page: FolioReaderPage)

    /**
     Notifies that page did load. A page load doesn't mean that this page is displayed right away, use `pageDidAppear` to get informed about the appearance of a page.

     - parameter page: The loaded page
     */
    @objc optional func pageDidLoad(_ page: FolioReaderPage)
    
    /**
     Notifies that page content is in a ready state.

     - parameter page: The loaded page
     */
    @objc optional func pageIsReady(_ page: FolioReaderPage)
    
    /**
     Notifies that page receive tap gesture.
     
     - parameter recognizer: The tap recognizer
     */
    @objc optional func pageTap(_ recognizer: UITapGestureRecognizer)
}

open class FolioReaderPage: UICollectionViewCell, UIGestureRecognizerDelegate, WKNavigationDelegate {
    weak var delegate: FolioReaderPageDelegate?
    weak var readerContainer: FolioReaderContainer?

    /// The index of the current page. Note: The index start at 1!
    open var pageNumber: Int!
    var webView: FolioReaderWKWebView?
    
    fileprivate var colorView: UIView!
    
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

    // MARK: - View life cicle

    public override init(frame: CGRect) {
        // Init explicit attributes with a default value. The `setup` function MUST be called to configure the current object with valid attributes.
        self.readerContainer = FolioReaderContainer(withConfig: FolioReaderConfig(), folioReader: FolioReader(), epubPath: "")
        super.init(frame: frame)
        self.backgroundColor = UIColor.clear

        NotificationCenter.default.addObserver(self, selector: #selector(refreshPageMode), name: NSNotification.Name(rawValue: "needRefreshPageMode"), object: nil)
    }

    public func setup(withReaderContainer readerContainer: FolioReaderContainer) {
        self.readerContainer = readerContainer
        guard let readerContainer = self.readerContainer else { return }

        if webView == nil {
            webView = FolioReaderWKWebView(frame: webViewFrame(), readerContainer: readerContainer)
            webView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            webView?.scrollView.showsVerticalScrollIndicator = false
            webView?.scrollView.showsHorizontalScrollIndicator = false
            webView?.backgroundColor = .clear
            self.contentView.addSubview(webView!)
        }
        webView?.navigationDelegate = self

        if colorView == nil {
            colorView = UIView()
            colorView.backgroundColor = self.readerConfig.nightModeBackground
            webView?.scrollView.addSubview(colorView)
        }

        // Remove all gestures before adding new one
        webView?.gestureRecognizers?.forEach({ gesture in
            webView?.removeGestureRecognizer(gesture)
        })
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        tapGestureRecognizer.numberOfTapsRequired = 1
        tapGestureRecognizer.delegate = self
        webView?.addGestureRecognizer(tapGestureRecognizer)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("storyboards are incompatible with truth and beauty")
    }

    deinit {
        webView?.scrollView.delegate = nil
        webView?.navigationDelegate = nil
        NotificationCenter.default.removeObserver(self)
    }

    override open func layoutSubviews() {
        super.layoutSubviews()

        webView?.setupScrollDirection()
        webView?.frame = webViewFrame()
    }

    func webViewFrame() -> CGRect {
        guard (self.readerConfig.hideBars == false) else {
            return bounds
        }

        let statusbarHeight = UIApplication.shared.statusBarFrame.size.height
        let navBarHeight = self.folioReader.readerCenter?.navigationController?.navigationBar.frame.size.height ?? CGFloat(0)
        let navTotal = self.readerConfig.shouldHideNavigationOnTap ? 0 : statusbarHeight + navBarHeight
        let paddingTop: CGFloat = 20
        let paddingBottom: CGFloat = 30

        return CGRect(
            x: bounds.origin.x,
            y: self.readerConfig.isDirection(bounds.origin.y + navTotal, bounds.origin.y + navTotal + paddingTop, bounds.origin.y + navTotal),
            width: bounds.width,
            height: self.readerConfig.isDirection(bounds.height - navTotal, bounds.height - navTotal - paddingTop - paddingBottom, bounds.height - navTotal)
        )
    }

    func loadHTMLString(_ htmlContent: String!, baseURL: URL!) {
        // Insert the stored highlights to the HTML
        let tempHtmlContent = htmlContentWithInsertHighlights(htmlContent)
        // Load the html into the webview
        webView?.alpha = 0
        webView?.loadHTMLString(tempHtmlContent, baseURL: baseURL)
    }

    // MARK: - Highlights
    
    open func selectedHighlight(completion: @escaping (Highlight?) -> Void) {
        webView?.js("getHighlightId()", completion: { highlightId in
            guard let highlightId = highlightId as? String, let highlight = Highlight.getById(withConfiguration: self.readerConfig, highlightId: highlightId) else {
                completion(nil)
                return
            }
            
            completion(highlight)
        })
    }
    
    open func highlight(_ sender: UIMenuController?) {
        self.webView?.highlight(sender)
    }

    fileprivate func htmlContentWithInsertHighlights(_ htmlContent: String) -> String {
        var tempHtmlContent = htmlContent as NSString
        // Restore highlights
        guard let bookId = (self.book.name as NSString?)?.deletingPathExtension else {
            return tempHtmlContent as String
        }

        let highlights = Highlight.allByBookId(withConfiguration: self.readerConfig, bookId: bookId, andPage: pageNumber as NSNumber?)

        if (highlights.count > 0) {
            for item in highlights {
                let style = HighlightStyle.classForStyle(item.type)
                
                var tag = ""
                if let _ = item.noteForHighlight {
                    tag = "<highlight id=\"\(item.highlightId!)\" onclick=\"callHighlightWithNoteURL(this);\" class=\"\(style)\">\(item.content!)</highlight>"
                } else {
                    tag = "<highlight id=\"\(item.highlightId!)\" onclick=\"callHighlightURL(this);\" class=\"\(style)\">\(item.content!)</highlight>"
                }
                
                var locator = item.contentPre + item.content
                locator += item.contentPost
                locator = Highlight.removeSentenceSpam(locator) /// Fix for Highlights
                
                let range: NSRange = tempHtmlContent.range(of: locator, options: .literal)
                
                if range.location != NSNotFound {
                    let newRange = NSRange(location: range.location + item.contentPre.count, length: item.content.count)
                    tempHtmlContent = tempHtmlContent.replacingCharacters(in: newRange, with: tag) as NSString
                } else {
                    print("highlight range not found")
                }
            }
        }
        return tempHtmlContent as String
    }

    // MARK: - UIWebView Delegate
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let webView = webView as? FolioReaderWKWebView else {
            return
        }
        
        delegate?.pageWillLoad?(self)

        // Add the custom class based onClick listener
        self.setupClassBasedOnClickListeners()

        refreshPageMode()

        if self.readerConfig.enableTTS && !self.book.hasAudio {
            webView.js("wrappingSentencesWithinPTags()")

            if let audioPlayer = self.folioReader.readerAudioPlayer, (audioPlayer.isPlaying() == true) {
                audioPlayer.readCurrentSentence()
            }
        }

        let direction: ScrollDirection = self.folioReader.needsRTLChange ? .positive(withConfiguration: self.readerConfig) : .negative(withConfiguration: self.readerConfig)
        
        switch self.readerConfig.scrollDirection {
        case .vertical, .defaultVertical, .horizontalWithVerticalContent:
            webView.js("document.getElementById(\'page\').style.height = \"auto\"", completion: { result in

            })
            break
        case .horizontal:
            webView.js("document.getElementById(\"page\").style.height = \"100vh\"", completion: { result in
                
            })

            break
        }
        
        self.delegate?.pageDidLoad?(self)
        
        webView.js("document.readyState") { result in
            let contentReadyBlock = {
                self.delegate?.pageIsReady?(self)
                
                UIView.animate(withDuration: 0.2, animations: {webView.alpha = 1}, completion: { finished in
                    webView.isColors = false
                    self.webView?.createMenu(options: false)
                })
            }
           
            if (self.folioReader.readerCenter?.pageScrollDirection == direction && self.readerConfig.scrollDirection != .horizontalWithVerticalContent) {
                self.scrollPageToBottom { _ in
                    contentReadyBlock()
                }
            } else {
                contentReadyBlock()
            }
        }
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let request = navigationAction.request
        let navigationType = navigationAction.navigationType
        
        guard let webView = webView as? FolioReaderWKWebView, let scheme = request.url?.scheme else {
            decisionHandler(.allow)
            return
        }
        
        guard let url = request.url else {
            decisionHandler(.cancel)
            return
        }
        
        if scheme == "highlight" || scheme == "highlight-with-note" {
            guard let decoded = url.absoluteString.removingPercentEncoding else {
                decisionHandler(.cancel)
                return
            }
            
            let index = decoded.index(decoded.startIndex, offsetBy: 12)
            let rect = NSCoder.cgRect(for: String(decoded[index...]))

            webView.createMenu(options: true)
            webView.setMenuVisible(true, andRect: rect)
            
            decisionHandler(.cancel)
            return
        }
        
        if scheme == "play-audio" {
            guard let decoded = url.absoluteString.removingPercentEncoding else {
                decisionHandler(.cancel)
                return
            }
            
            let index = decoded.index(decoded.startIndex, offsetBy: 13)
            let playID = String(decoded[index...])
            let chapter = self.folioReader.readerCenter?.getCurrentChapter()
            let href = chapter?.href ?? ""
            self.folioReader.readerAudioPlayer?.playAudio(href, fragmentID: playID)
            
            decisionHandler(.cancel)
            return
        }
        
        if scheme == "file" {
            let anchorFromURL = url.fragment

            // Handle internal url
            if url.pathExtension.isEmpty == false {
                let pathComponent = (self.book.opfResource.href as NSString?)?.deletingLastPathComponent
                guard let base = ((pathComponent == nil || pathComponent?.isEmpty == true) ? self.book.name : pathComponent) else {
                    decisionHandler(.allow)
                    return
                }

                let path = url.path
                let splitedPath = path.components(separatedBy: base)

                // Return to avoid crash
                if (splitedPath.count <= 1 || splitedPath[1].isEmpty) {
                    decisionHandler(.allow)
                    return
                }

                let href = splitedPath[1].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let hrefPage = (self.folioReader.readerCenter?.findPageByHref(href) ?? 0) + 1

                if (hrefPage == pageNumber) {
                    // Handle internal #anchor
                    if anchorFromURL != nil {
                        handleAnchor(anchorFromURL!, avoidBeginningAnchors: false, animated: true)
                        decisionHandler(.cancel)
                        return
                    }
                } else {
                    self.folioReader.readerCenter?.changePageWith(href: href, animated: true)
                }
                
                decisionHandler(.cancel)
                return
            }

            // Handle internal #anchor
            if anchorFromURL != nil {
                handleAnchor(anchorFromURL!, avoidBeginningAnchors: false, animated: true)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
            return
        }
        
        if scheme == "mailto" {
            print("Email")
            decisionHandler(.allow)
            return
        }
        
        if url.absoluteString != "about:blank" && scheme.contains("http") && navigationType == .linkActivated {
            let safariVC = SFSafariViewController(url: request.url!)
            safariVC.view.tintColor = self.readerConfig.tintColor
            self.folioReader.readerCenter?.present(safariVC, animated: true, completion: nil)
            decisionHandler(.cancel)
            return
        }
        
        
        // Check if the url is a custom class based onClick listerner
        var isClassBasedOnClickListenerScheme = false
        for listener in self.readerConfig.classBasedOnClickListeners {

            if scheme == listener.schemeName,
                let absoluteURLString = request.url?.absoluteString,
                let range = absoluteURLString.range(of: "/clientX=") {
                let baseURL = String(absoluteURLString[..<range.lowerBound])
                let positionString = String(absoluteURLString[range.lowerBound...])
                if let point = getEventTouchPoint(fromPositionParameterString: positionString) {
                    let attributeContentString = (baseURL.replacingOccurrences(of: "\(scheme)://", with: "").removingPercentEncoding)
                    // Call the on click action block
                    listener.onClickAction(attributeContentString, point)
                    // Mark the scheme as class based click listener scheme
                    isClassBasedOnClickListenerScheme = true
                }
            }
        }

        if isClassBasedOnClickListenerScheme == false {
            // Try to open the url with the system if it wasn't a custom class based click listener
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.openURL(url)
                decisionHandler(.cancel)
                return
            }
        } else {
            decisionHandler(.cancel)
            return
        }
        
        decisionHandler(.allow)
    }

    fileprivate func getEventTouchPoint(fromPositionParameterString positionParameterString: String) -> CGPoint? {
        // Remove the parameter names: "/clientX=188&clientY=292" -> "188&292"
        var positionParameterString = positionParameterString.replacingOccurrences(of: "/clientX=", with: "")
        positionParameterString = positionParameterString.replacingOccurrences(of: "clientY=", with: "")
        // Separate both position values into an array: "188&292" -> [188],[292]
        let positionStringValues = positionParameterString.components(separatedBy: "&")
        // Multiply the raw positions with the screen scale and return them as CGPoint
        if
            positionStringValues.count == 2,
            let xPos = Int(positionStringValues[0]),
            let yPos = Int(positionStringValues[1]) {
            return CGPoint(x: xPos, y: yPos)
        }
        return nil
    }

    // MARK: Gesture recognizer

    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer.view is FolioReaderWKWebView {
            if otherGestureRecognizer is UILongPressGestureRecognizer {
                return false
            }
            
            return true
        }
        
        return false
    }

    @objc open func handleTapGesture(_ recognizer: UITapGestureRecognizer) {
        self.delegate?.pageTap?(recognizer)
        
        var menuWasVisible = self.webView?.menuIsVisible
        
        if menuWasVisible == true {
            webView?.setMenuVisible(false)
        }
        
        if let _navigationController = self.folioReader.readerCenter?.navigationController, (_navigationController.isNavigationBarHidden == true) {
            webView?.js("getSelectedText()", completion: { selected in
                if ((selected as? String)?.isEmpty == false) {
                    return
                }
                
                let delay = 0.4 * Double(NSEC_PER_SEC) // 0.4 seconds * nanoseconds per seconds
                let dispatchTime = (DispatchTime.now() + (Double(Int64(delay)) / Double(NSEC_PER_SEC)))
                
                DispatchQueue.main.asyncAfter(deadline: dispatchTime, execute: {
                    if (self.webView?.menuIsVisible == false && menuWasVisible == false) {
                        self.folioReader.readerCenter?.toggleBars()
                    }
                })
            })
        } else if (self.readerConfig.shouldHideNavigationOnTap == true) {
            self.folioReader.readerCenter?.hideBars()
        }
    }

    // MARK: - Public scroll postion setter

    /**
     Scrolls the page to a given offset

     - parameter offset:   The offset to scroll
     - parameter animated: Enable or not scrolling animation
     */
    open func scrollPageToOffset(_ offset: CGFloat, animated: Bool) {
        let pageOffsetPoint = self.readerConfig.isDirection(CGPoint(x: 0, y: offset), CGPoint(x: offset, y: 0), CGPoint(x: 0, y: offset))
        webView?.scrollView.setContentOffset(pageOffsetPoint, animated: animated)
        
        webView?.scrollPageToPoint(pageOffsetPoint)
    }

    /**
     Scrolls the page to bottom
     */
    open func scrollPageToBottom(completion: ((Error?)->Void)? = nil) {
        guard let webView = webView else {
            return
        }
        
        webView.getContentDimensions { dimensions in
            guard let dimensions = dimensions else {
                return
            }
            
            let offset = dimensions.offsetForLastPage(usingConfiguration: self.readerConfig)
            
            webView.scrollPageToPoint(offset, completion: completion)
        }
    }

    /**
     Handdle #anchors in html, get the offset and scroll to it

     - parameter anchor:                The #anchor
     - parameter avoidBeginningAnchors: Sometimes the anchor is on the beggining of the text, there is not need to scroll
     - parameter animated:              Enable or not scrolling animation
     */
    open func handleAnchor(_ anchor: String,  avoidBeginningAnchors: Bool, animated: Bool) {
        guard anchor.isEmpty == false else {
            return
        }

        getAnchorOffset(anchor) { offset in
            switch self.readerConfig.scrollDirection {
            case .vertical, .defaultVertical:
                let isBeginning = (offset < self.frame.forDirection(withConfiguration: self.readerConfig) * 0.5)

                if !avoidBeginningAnchors {
                    self.scrollPageToOffset(offset, animated: animated)
                } else if avoidBeginningAnchors && !isBeginning {
                    self.scrollPageToOffset(offset, animated: animated)
                }
            case .horizontal, .horizontalWithVerticalContent:
                self.scrollPageToOffset(offset, animated: animated)
            }
        }
    }

    // MARK: Helper

    /**
     Get the #anchor offset in the page

     - parameter anchor: The #anchor id
     - returns: The element offset ready to scroll
     */
    func getAnchorOffset(_ anchor: String, completion: @escaping (CGFloat) -> Void) {
        let horizontal = self.readerConfig.scrollDirection == .horizontal
        
        webView?.js("getAnchorOffset('\(anchor)', \(horizontal.description))", completion: { strOffset in
            guard let strOffset = strOffset as? NSString else {
                completion(CGFloat(0))
                return
            }
            
            completion(CGFloat(strOffset.floatValue))
        })
    }

    // MARK: Mark ID

    /**
     Audio Mark ID - marks an element with an ID with the given class and scrolls to it

     - parameter identifier: The identifier
     */
    func audioMarkID(_ identifier: String) {
        guard let currentPage = self.folioReader.readerCenter?.currentPage else {
            return
        }

        let playbackActiveClass = self.book.playbackActiveClass
        currentPage.webView?.js("audioMarkID('\(playbackActiveClass)','\(identifier)')")
    }

    // MARK: UIMenu visibility

    override open func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard let webView = webView else { return false }

        if UIMenuController.shared.menuItems?.count == 0 {
            webView.isColors = false
            webView.createMenu(options: false)
        }

        if !webView.isShare && !webView.isColors {
            webView.js("getSelectedText()") { result in
                guard let result = result as? String, result.components(separatedBy: " ").count == 1 else {
                    webView.isOneWord = false
                    return
                }
                
                webView.isOneWord = true
                webView.createMenu(options: false)
            }
        }

        return super.canPerformAction(action, withSender: sender)
    }

    // MARK: ColorView fix for horizontal layout
    @objc func refreshPageMode() {
        guard let webView = webView else { return }

        if (self.folioReader.nightMode == true) {
            // omit create webView and colorView
            webView.js("document.documentElement.offsetHeight") { contentHeight in
                guard let contentHeight = contentHeight as? String else {
                    return
                }
                
                let frameHeight = webView.frame.height
                let lastPageHeight = CGFloat(frameHeight) * CGFloat(webView.pageCount) - CGFloat(Double(contentHeight)!)
                self.colorView.frame = CGRect(x: webView.frame.width * CGFloat(webView.pageCount-1), y: webView.frame.height - lastPageHeight, width: webView.frame.width, height: lastPageHeight)
            }
        } else {
            colorView.frame = CGRect.zero
        }
    }
    
    // MARK: - Class based click listener
    
    fileprivate func setupClassBasedOnClickListeners() {
        for listener in self.readerConfig.classBasedOnClickListeners {
            self.webView?.js("addClassBasedOnClickListener(\"\(listener.schemeName)\", \"\(listener.querySelector)\", \"\(listener.attributeName)\", \"\(listener.selectAll)\")");
        }
    }
    
}
