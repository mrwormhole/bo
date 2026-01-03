#include "tree.h"

/* Faster uid/gid -> name lookup with hash(tm)(r)(c) tables! */
#define HASH(x)		((x)&255)
struct xtable *gtable[256], *utable[256];

#define inohash(x)	((x)&255)
struct inotable *itable[256];

char *uidtoname(uid_t uid)
{
  struct xtable *o, *p, *t;
  struct passwd *ent;
  char ubuf[32];
  int uent = HASH(uid);
  
  for(o = p = utable[uent]; p ; p=p->nxt) {
    if (uid == p->xid) return p->name;
    else if (uid < p->xid) break;
    o = p;
  }
  /* Not found, do a real lookup and add to table */
  t = xmalloc(sizeof(struct xtable));
  if ((ent = getpwuid(uid)) != NULL) t->name = scopy(ent->pw_name);
  else {
    snprintf(ubuf,30,"%d",uid);
    ubuf[31] = 0;
    t->name = scopy(ubuf);
  }
  t->xid = uid;
  t->nxt = p;
  if (p == utable[uent]) utable[uent] = t;
  else o->nxt = t;
  return t->name;
}

char *gidtoname(gid_t gid)
{
  struct xtable *o, *p, *t;
  struct group *ent;
  char gbuf[32];
  int gent = HASH(gid);
  
  for(o = p = gtable[gent]; p ; p=p->nxt) {
    if (gid == p->xid) return p->name;
    else if (gid < p->xid) break;
    o = p;
  }
  /* Not found, do a real lookup and add to table */
  t = xmalloc(sizeof(struct xtable));
  if ((ent = getgrgid(gid)) != NULL) t->name = scopy(ent->gr_name);
  else {
    snprintf(gbuf,30,"%d",gid);
    gbuf[31] = 0;
    t->name = scopy(gbuf);
  }
  t->xid = gid;
  t->nxt = p;
  if (p == gtable[gent]) gtable[gent] = t;
  else o->nxt = t;
  return t->name;
}

/* Record inode numbers of followed sym-links to avoid re-following them */
void saveino(ino_t inode, dev_t device)
{
  struct inotable *it, *ip, *pp;
  int hp = inohash(inode);

  for(pp = ip = itable[hp];ip;ip = ip->nxt) {
    if (ip->inode > inode) break;
    if (ip->inode == inode && ip->device >= device) break;
    pp = ip;
  }

  if (ip && ip->inode == inode && ip->device == device) return;

  it = xmalloc(sizeof(struct inotable));
  it->inode = inode;
  it->device = device;
  it->nxt = ip;
  if (ip == itable[hp]) itable[hp] = it;
  else pp->nxt = it;
}

bool findino(ino_t inode, dev_t device)
{
  struct inotable *it;

  for(it=itable[inohash(inode)]; it; it=it->nxt) {
    if (it->inode > inode) break;
    if (it->inode == inode && it->device >= device) break;
  }

  if (it && it->inode == inode && it->device == device) return true;
  return false;
}
