//
//  AsyncFetcher.swift
//  Haneke
//
//  Created by Hermes Pique on 1/2/16.
//  Copyright © 2016 Haneke. All rights reserved.
//

import Foundation
@testable import Haneke

class AsyncFetcher<T : DataConvertible> : Fetcher<T> {

    let getValue : () -> T.Result

    init(key: String, value getValue : @autoclosure @escaping () -> T.Result) {
        self.getValue = getValue
        super.init(key: key)
    }

    override func fetch(failure fail: ((NSError?) -> ()), success succeed: (T.Result) -> ()) {
        let value = getValue()
        dispatch_get_global_queue(DispatchQueue.GlobalQueuePriority.default, 0).async {
            DispatchQueue.main.async {
                succeed(value)
            }
        }
    }

    override func cancelFetch() {}

}
