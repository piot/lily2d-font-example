# Font Example

Example of rendering a MSDF fonts in [Lily2D](https://lily2d.com/).

SDF fonts have been around since 2007 (Valve Software), but I didn't really like them - hard edges became round or blurred.
Around 2025 [@catnipped](https://bsky.app/profile/ossianboren.bsky.social) sent me a link to an blog about [MSDF](https://www.redblobgames.com/articles/sdf-fonts/), and it was very exciting!

## Create font

```sh
msdf-bmfont --reuse -o assets/fonts/example.png -m 512,256 -s 42 -r 3 -p 1 -t msdf YourFont.ttf
```

## References

- [msdf-bmfont-xml](https://github.com/soimy/msdf-bmfont-xml)
- [sdf-fonts](https://www.redblobgames.com/articles/sdf-fonts/)
- [msdf-bmfont](https://msdf-bmfont.donmccurdy.com/)
- [msdfgen (written in C)](https://github.com/Chlumsky/msdfgen)
- [Perfecting anti-aliasing on signed distance functions](https://blog.pkh.me/p/44-perfecting-anti-aliasing-on-signed-distance-functions.html)

Copyright (c) 2026 Peter Bjorklund. Feel free to use the code in your projects!
