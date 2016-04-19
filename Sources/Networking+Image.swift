#if os(iOS) || os(tvOS) || os(watchOS)

import Foundation
import UIKit

public extension Networking {
    /**
     Downloads an image using the specified path.
     - parameter path: The full path where the image is located
     - parameter completion: A closure that gets called when the image download request is completed, it contains an `UIImage` object and a `NSError`.
     */
    public func downloadImage(fullPath path: String, completion: (image: UIImage?, error: NSError?) -> ()) {
        guard let encodedPath = path.encodeUTF8() else { fatalError("Couldn't encode path to UTF8: \(path)") }
        guard let fullURL = NSURL(string: encodedPath) else { fatalError("Couldn't create a NSURL from encoded path: \(encodedPath)") }
        guard let url = NSURL(string: (fullURL.absoluteString as NSString).stringByReplacingOccurrencesOfString("/", withString: "-")),
            cachesURL = NSFileManager.defaultManager().URLsForDirectory(.CachesDirectory, inDomains: .UserDomainMask).first else { fatalError("Couldn't normalize url") }
        let destinationURL = cachesURL.URLByAppendingPathComponent(url.absoluteString)
        guard let filePath = destinationURL.path else { fatalError("File path not valid") }

        self.downloadImage(requestURL: fullURL, destinationURL: destinationURL, path: encodedPath, filePath: filePath, completion: completion)
    }

    /**
     Downloads an image using the specified path.
     - parameter path: The path where the image is located
     - parameter completion: A closure that gets called when the image download request is completed, it contains an `UIImage` object and a `NSError`.
     */
    public func downloadImage(path: String, completion: (image: UIImage?, error: NSError?) -> ()) {
        let destinationURL = self.destinationURL(path)
        guard let filePath = self.destinationURL(path).path else { fatalError("File path not valid") }

        self.downloadImage(requestURL: self.urlForPath(path), destinationURL: destinationURL, path: path, filePath: filePath, completion: completion)
    }

    func downloadImage(requestURL requestURL: NSURL, destinationURL: NSURL, path: String, filePath: String, completion: (image: UIImage?, error: NSError?) -> ()) {
        if let getFakeRequests = self.fakeRequests[.GET], fakeRequest = getFakeRequests[path] {
            if fakeRequest.statusCode.statusCodeType() == .Successful, let image = fakeRequest.response as? UIImage {
                completion(image: image, error: nil)
            } else {
                let error = NSError(domain: Networking.ErrorDomain, code: fakeRequest.statusCode, userInfo: [NSLocalizedDescriptionKey : NSHTTPURLResponse.localizedStringForStatusCode(fakeRequest.statusCode)])
                completion(image: nil, error: error)
            }
        } else if let image = self.imageCache.objectForKey(destinationURL.absoluteString) as? UIImage {
            completion(image: image, error: nil)
        } else if NSFileManager().fileExistsAtPath(filePath) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), {
                if let data = NSData(contentsOfURL: destinationURL), image = UIImage(data: data) {
                    dispatch_async(dispatch_get_main_queue(), {
                        completion(image: image, error: nil)
                    })
                    self.imageCache.setObject(image, forKey: destinationURL.absoluteString)
                }
            })
        } else {
            let request = NSMutableURLRequest(URL: requestURL)
            request.HTTPMethod = RequestType.GET.rawValue
            request.addValue("application/json", forHTTPHeaderField: "Accept")

            if let token = token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let semaphore = dispatch_semaphore_create(0)
            var returnedData: NSData?
            var returnedImage: UIImage?
            var returnedError: NSError?
            var returnedResponse: NSURLResponse?

            NetworkActivityIndicator.sharedIndicator.visible = true

            self.session.downloadTaskWithRequest(request, completionHandler: { url, response, error in
                returnedResponse = response
                returnedError = error

                if returnedError == nil, let url = url, data = NSData(contentsOfURL: url), image = UIImage(data: data) {
                    returnedData = data
                    returnedImage = image

                    data.writeToURL(destinationURL, atomically: true)
                    self.imageCache.setObject(image, forKey: destinationURL.absoluteString)
                } else if let url = url {
                    if let response = response as? NSHTTPURLResponse {
                        returnedError = NSError(domain: Networking.ErrorDomain, code: response.statusCode, userInfo: [NSLocalizedDescriptionKey : NSHTTPURLResponse.localizedStringForStatusCode(response.statusCode)])
                    } else {
                        returnedError = NSError(domain: Networking.ErrorDomain, code: 500, userInfo: [NSLocalizedDescriptionKey : "Failed to load url: \(url.absoluteString)"])
                    }
                }

                if TestCheck.isTesting && self.disableTestingMode == false {
                    dispatch_semaphore_signal(semaphore)
                } else {
                    dispatch_async(dispatch_get_main_queue(), {
                        NetworkActivityIndicator.sharedIndicator.visible = false

                        self.logError(.JSON, parameters: nil, data: returnedData, request: request, response: response, error: returnedError)
                        completion(image: returnedImage, error: returnedError)
                    })
                }
            }).resume()

            if TestCheck.isTesting && self.disableTestingMode == false {
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)

                self.logError(.JSON, parameters: nil, data: returnedData, request: request, response: returnedResponse, error: returnedError)
                completion(image: returnedImage, error: returnedError)
            }
        }
    }

    /**
     Cancels the image download request for the specified path. This causes the request to complete with error code -999
     - parameter path: The path for the cancelled image download request
     */
    public func cancelImageDownload(path: String) {
        self.cancelRequest(.Download, requestType: .GET, path: path)
    }

    /**
     Registers a fake download image request with an UIImage. After registering this, every download request to the path, will return
     the registered UIImage.
     - parameter path: The path for the faked image download request.
     - parameter image: A UIImage that will be returned when there's a request to the registered path
     */
    public func fakeImageDownload(path: String, image: UIImage?, statusCode: Int = 200) {
        self.fake(.GET, path: path, response: image, statusCode: statusCode)
    }
}

#endif