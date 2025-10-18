# So basically, it's a TrollDecrypt
#### But it can help you download iOS app that require higher iOS minimum in Appstore and then decrypt it.

# Did it actually work?
##### Bascially yes, at some point. On the source code I publish, sometimes it works, sometimes don't, I'll explain the method details. If you want to contribute to it then the PR is on top of the page! You're welcome!

# How did the decrypt 'works'?
##### So on a random day, [DuyTran](https://github.com/khanhduytran0) told me that he saw a reddit post that someone said an online telegram bot can decrypt iOS that require minimum is iOS 26, I also remember myself i used to install higher iOS app on my iPhone with [appstoretroller](https://github.com/verygenericname/appstoretroller) (thanks to Mineek and Nathan) to install app.

##### The author of the post seems not sharing the method but luckily DuyTran found it out. He started lldb and attach --waitfor it, run until right before the app loaded fully FairPlay (LC_ENCRYPTION_INFO/LC_ENCRYPTION_INFO64) and hit `abort()`. From that we can decrypt the app without need it fully running/loaded, just make sure the app is loaded at least 0x4000 pages right after run and then decrypt the FairPlay and it's done.

# So how it's going?
##### Currently the app is still not finish/under develop because i cannot set lldb automatically, if you have a time and interested with this, please help us to finish this project (at least this help Sideload community alive before we have a newer jailbreak).

# Credits
- [fiore](https://github.com/donato-fiore) for [TrollDecrpyt](https://github.com/donato-fiore/TrollDecrypt)
- [Mineek](https://github.com/mineek) and [Nathan](https://github.com/verygenericname) for [appstoretroller](https://github.com/verygenericname/appstoretroller)
- [DuyTran](https://github.com/khanhduytran0) for the idea and method