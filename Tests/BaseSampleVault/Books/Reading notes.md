---
tags: [reading]
---
# Reading notes

Books I am reading right now:

```base
filters:
  and:
    - file.hasTag("book")
    - 'status == "reading" || status == "to-read"'
views:
  - type: list
    name: Up next
    order:
      - file.name
      - author
      - pages
```

Everything by genre: ![[Books.base#Gallery]]
